-- Boundary: Suwayomi home screen presentation.
--
-- Responsibility: show the library as a full-screen ListMenu while keeping
-- the KOReader top bar / FileManager menu touch zones accessible.
-- Owned state: the ListMenu and its passthrough handleEvent wrapper.
-- Dependencies: ListMenu, KOReader uimanager, FileManager touch zones.
-- External data: rendered on top of FileManager via UIManager:show.

local UIManager = require("ui/uimanager")

local I18n     = require("suwayomi/i18n")
local ListMenu = require("suwayomi/ui/list_menu")
local ListRows = require("suwayomi/ui/list_rows")

local SuwayomiHome = {}

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
end

function SuwayomiHome.show(manga_list, onSelectCallback, options)
    options = options or {}
    options.title = options.title or I18n.t("Suwayomi Library")
    options.grid = options.grid ~= false
    options.item_table = ListRows.buildMangaMenuTable(manga_list or {}, {
        show_in_library = false,
        on_select = onSelectCallback,
    })
    local menu = ListMenu.create(options)
    installGesturePassthrough(menu)
    UIManager:show(menu)
    return menu
end

return SuwayomiHome
