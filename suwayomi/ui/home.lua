-- Boundary: Suwayomi home screen presentation.
--
-- Responsibility: show the library as a full-screen ListMenu with a custom
-- top status bar and FileManager top-bar passthrough.
-- Owned state: the ListMenu and its passthrough handleEvent wrapper.
-- Dependencies: ListMenu, SuwayomiStatusBar, KOReader widgets and status modules.
-- External data: rendered on top of FileManager via UIManager:show.

local UIManager = require("ui/uimanager")
local Device    = require("device")

local ListMenu       = require("suwayomi/ui/list_menu")
local ListRows       = require("suwayomi/ui/list_rows")
local SuwayomiStatusBar = require("suwayomi/ui/status_bar")

local SuwayomiHome = {}

local function buildStatusStrings()
    local left_parts = {}
    local right_parts = {}

    local ok_dt, datetime = pcall(require, "datetime")
    if ok_dt and datetime and datetime.secondsToHour then
        local twelve_hour = _G.G_reader_settings
            and _G.G_reader_settings:isTrue("twelve_hour_clock")
        local time_str = datetime.secondsToHour(os.time(), twelve_hour)
        if time_str then
            table.insert(left_parts, time_str)
        end
    end

    if Device:hasBattery() then
        local powerd = Device:getPowerDevice()
        if powerd and powerd.getCapacity then
            table.insert(right_parts, tostring(powerd:getCapacity()) .. "%")
        end
    end

    local ok_net, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_net and NetworkMgr and type(NetworkMgr.isWifiOn) == "function"
            and NetworkMgr:isWifiOn() then
        table.insert(right_parts, "Wi-Fi")
    end

    local left = #left_parts > 0 and table.concat(left_parts, " ") or " "
    local right = #right_parts > 0 and table.concat(right_parts, " · ") or " "
    return left, right
end

local function updateStatusBar(menu)
    if not menu.title_bar then
        return
    end
    local left, right = buildStatusStrings()
    if menu.title_bar.setTitle then
        menu.title_bar:setTitle(left)
    end
    if menu.title_bar.setSubTitle then
        menu.title_bar:setSubTitle(right)
    end
end

local function scheduleStatusRefresh(menu)
    if menu._suwayomi_status_update then
        UIManager:unschedule(menu._suwayomi_status_update)
    end
    menu._suwayomi_status_update = function()
        updateStatusBar(menu)
        scheduleStatusRefresh(menu)
    end
    UIManager:scheduleIn(60, menu._suwayomi_status_update)
end

local function forwardEventToFileManager(event)
    local NEVER_FORWARD = {
        onCloseWidget   = true,
        onFlushSettings = true,
        onShow          = true,
        onClose         = true,
    }

    if NEVER_FORWARD[event.handler] then
        return nil
    end

    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    if not ok or not FileManager then
        return nil
    end
    local fm = FileManager.instance
    if not fm or fm == SuwayomiHome then
        return nil
    end
    return fm:handleEvent(event)
end

local function installGesturePassthrough(menu)
    local original_handleEvent = menu.handleEvent
    menu.handleEvent = function(self, event)
        if original_handleEvent(self, event) then
            return true
        end

        if event.handler == "onGesture" then
            local ev = (event.args or {})[1]
            if ev then
                local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
                if ok and FileManager then
                    local fm = FileManager.instance
                    if fm and fm.menu and fm.menu._ordered_touch_zones then
                        for _, tzone in ipairs(fm.menu._ordered_touch_zones) do
                            if tzone.gs_range:match(ev) and tzone.handler(ev) then
                                return true
                            end
                        end
                    end
                end
            end
            return false
        end

        return forwardEventToFileManager(event)
    end

    local original_onCloseWidget = menu.onCloseWidget
    menu.onCloseWidget = function(self, ...)
        if self._suwayomi_status_update then
            UIManager:unschedule(self._suwayomi_status_update)
            self._suwayomi_status_update = nil
        end
        if original_onCloseWidget then
            return original_onCloseWidget(self, ...)
        end
    end
end

function SuwayomiHome.show(manga_list, onSelectCallback, options)
    options = options or {}
    local left, right = buildStatusStrings()
    options.title = nil
    options.grid = options.grid ~= false
    options.item_table = ListRows.buildMangaMenuTable(manga_list or {}, {
        show_in_library = false,
        on_select = onSelectCallback,
    })
    for _, item in ipairs(options.item_table) do
        item.keep_menu_open = true
    end
    options.custom_title_bar = SuwayomiStatusBar:new{
        left_text = left,
        right_text = right,
    }
    local menu = ListMenu.create(options)
    if menu.title_bar then
        menu.title_bar.show_parent = menu
    end
    installGesturePassthrough(menu)
    UIManager:show(menu)
    scheduleStatusRefresh(menu)
    return menu
end

return SuwayomiHome
