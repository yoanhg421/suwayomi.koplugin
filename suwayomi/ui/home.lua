-- Boundary: Suwayomi home screen widget.
--
-- Responsibility: present the library (and future home screens) as a full-screen
-- overlay that still lets the KOReader top bar and FileManager touch zones work.
-- Owned state: the wrapped ListMenu and active FileManager passthrough.
-- Dependencies: ListMenu, KOReader widget/geom/uimanager primitives.
-- External data: rendered as a child of UIManager on top of FileManager.

local InputContainer = require("ui/widget/container/inputcontainer")
local Geom           = require("ui/geometry")
local UIManager      = require("ui/uimanager")
local Device         = require("device")

local I18n     = require("suwayomi/i18n")
local ListMenu = require("suwayomi/ui/list_menu")
local ListRows = require("suwayomi/ui/list_rows")

local Screen = Device.screen

local SuwayomiHomeWidget = InputContainer:extend{
    name = "suwayomi_home",
    covers_fullscreen = false,
    is_popout = false,
}

function SuwayomiHomeWidget:init()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    local menu = ListMenu.create(self.menu_options or {})
    self[1] = menu
    self._suwayomi_menu = menu

    menu.close_callback = function()
        self:close()
        if self.on_close then
            self.on_close()
        end
    end
end

function SuwayomiHomeWidget:close()
    UIManager:close(self)
end

function SuwayomiHomeWidget:handleEvent(event)
    local NEVER_FORWARD = {
        onCloseWidget   = true,
        onFlushSettings = true,
        onShow          = true,
        onClose         = true,
    }

    if event.handler == "onGesture" then
        if InputContainer.handleEvent(self, event) then
            return true
        end

        local ev = (event.args or {})[1]
        if ev then
            local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
            if ok and FileManager then
                local fm = FileManager.instance
                local zone_lists = {}
                if fm and fm._ordered_touch_zones then
                    table.insert(zone_lists, fm._ordered_touch_zones)
                end
                if fm and fm.menu and fm.menu._ordered_touch_zones then
                    table.insert(zone_lists, fm.menu._ordered_touch_zones)
                end
                for _, zones in ipairs(zone_lists) do
                    for _, tzone in ipairs(zones) do
                        if tzone.gs_range:match(ev) and tzone.handler(ev) then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    if InputContainer.handleEvent(self, event) then
        return true
    end

    if NEVER_FORWARD[event.handler] then
        return
    end

    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    if not ok or not FileManager then
        return
    end
    local fm = FileManager.instance
    if fm and fm ~= self then
        return fm:handleEvent(event)
    end
end

local SuwayomiHome = {}

function SuwayomiHome.show(manga_list, onSelectCallback, options)
    options = options or {}
    options.title = options.title or I18n.t("Suwayomi Library")
    options.item_table = ListRows.buildMangaMenuTable(manga_list or {}, {
        show_in_library = false,
        on_select = onSelectCallback,
    })
    local home = SuwayomiHomeWidget:new{
        menu_options = options,
        on_close = options.close_callback,
    }
    UIManager:show(home)
    return home
end

return SuwayomiHome
