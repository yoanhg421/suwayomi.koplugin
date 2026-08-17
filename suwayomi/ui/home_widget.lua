-- Boundary: Suwayomi home widget wrapper.
--
-- Responsibility: host the ListMenu grid with a custom status bar and footer,
-- cover the full screen, and forward unhandled gestures to FileManager.
-- Owned state: the ListMenu child and the FileManager passthrough helpers.
-- Dependencies: ListMenu, InputContainer, KOReader UIManager and Device.

local UIManager = require("ui/uimanager")
local Device = require("device")
local InputContainer = require("ui/widget/container/inputcontainer")

local SuwayomiHomeWidget = InputContainer:extend{
    name = "suwayomi_home",
    covers_fullscreen = true,
}

local NEVER_FORWARD = {
    onCloseWidget   = true,
    onFlushSettings = true,
    onShow          = true,
    onClose         = true,
}

local ALLOW_TEARDOWN = {
    onExit    = true,
    onRestart = true,
}

local function carriesGesture(event)
    local args = event.args
    if type(args) ~= "table" then
        return false
    end
    for i = 1, 3 do
        local a = args[i]
        if type(a) == "table" and a.ges then
            return true
        end
    end
    return false
end

local function tryFileManagerZones(event)
    if event.handler ~= "onGesture" then
        return false
    end
    local ev = (event.args or {})[1]
    if not ev then
        return false
    end
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    if not ok or not FileManager then
        return false
    end
    local fm = FileManager.instance
    if not fm or not fm.menu or not fm.menu._ordered_touch_zones then
        return false
    end
    for _, tzone in ipairs(fm.menu._ordered_touch_zones) do
        if tzone.gs_range:match(ev) and tzone.handler(ev) then
            return true
        end
    end
    return false
end

local function forwardEventToFileManager(event, self_widget)
    if NEVER_FORWARD[event.handler] then
        return false
    end
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    if not ok or not FileManager then
        return false
    end
    local fm = FileManager.instance
    if not fm or fm == self_widget then
        return false
    end
    if tryFileManagerZones(event) then
        return true
    end
    if ALLOW_TEARDOWN[event.handler] and not carriesGesture(event) then
        return fm:handleEvent(event)
    end
    local saved_onClose = rawget(fm, "onClose")
    fm.onClose = function() return true end
    local ok_consumed, consumed = pcall(fm.handleEvent, fm, event)
    fm.onClose = saved_onClose
    return ok_consumed and consumed or false
end

function SuwayomiHomeWidget:init()
    if self.menu then
        self[1] = self.menu
        self.dimen = self.menu.dimen
        self.status_bar = self.menu.title_bar
        self.bottom_bar = self.menu._suwayomi_footer_widget
    end
end

function SuwayomiHomeWidget:_reopenAfterResize()
    if self._resize_reopen_pending then return end
    self._resize_reopen_pending = true
    UIManager:nextTick(function()
        self._resize_reopen_pending = false
        if not self._suwayomi_reopen then return end
        UIManager:close(self)
        self._suwayomi_reopen()
    end)
end

function SuwayomiHomeWidget:onSetDimensions()
    return self:_reopenAfterResize()
end

function SuwayomiHomeWidget:onScreenResize()
    return self:_reopenAfterResize()
end

function SuwayomiHomeWidget:onSetRotationMode(mode)
    local Screen = Device and Device.screen
    if not Screen or not mode or mode == Screen:getRotationMode() then
        return false
    end
    Screen:setRotationMode(mode)
    self:_reopenAfterResize()
    return true
end

local RESIZE_EVENTS = {
    onSetDimensions = true,
    onScreenResize = true,
    onSetRotationMode = true,
}

function SuwayomiHomeWidget:handleEvent(event)
    -- Resize/rotation events must be handled by the home widget BEFORE
    -- propagating to the Menu child. KOReader's Menu has its own
    -- onSetDimensions that calls _recalculateDimen with the cached
    -- inner_dimen, consuming the event before our handler can fire.
    if RESIZE_EVENTS[event.handler] then
        if InputContainer.handleEvent(self, event) then
            return true
        end
    end
    if self:propagateEvent(event) then
        return true
    end
    return forwardEventToFileManager(event, self)
end

return SuwayomiHomeWidget
