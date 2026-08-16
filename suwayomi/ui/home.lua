-- Boundary: Suwayomi home screen presentation.
--
-- Responsibility: build and show the full-screen Suwayomi home widget with a
-- tabbed bottom bar (Library, Downloads, Settings, Close) where each tab
-- renders its own ListMenu inside the home container.
-- Owned state: status refresh scheduling and the per-tab menu cache.
-- Dependencies: ListMenu, ListRows, DownloadsUI, SuwayomiStatusBar,
--               SuwayomiBottomBar, SuwayomiHomeWidget, UIManager, Device.

local UIManager = require("ui/uimanager")
local Device    = require("device")

local ListMenu       = require("suwayomi/ui/list_menu")
local ListRows       = require("suwayomi/ui/list_rows")
local DownloadsUI    = require("suwayomi/ui/downloads")
local SuwayomiStatusBar = require("suwayomi/ui/status_bar")
local SuwayomiBottomBar = require("suwayomi/ui/bottom_bar")
local SuwayomiHomeWidget = require("suwayomi/ui/home_widget")

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

local function buildLibraryMenu(manga_list, onSelectCallback, bottom_bar, home)
    local left, right = buildStatusStrings()
    local menu_options = {
        title = nil,
        grid = true,
        item_table = ListRows.buildMangaMenuTable(manga_list or {}, {
            show_in_library = false,
            on_select = onSelectCallback,
        }),
        custom_title_bar = SuwayomiStatusBar:new{
            left_text = left,
            right_text = right,
        },
        footer_widget = bottom_bar,
    }
    for _, item in ipairs(menu_options.item_table) do
        item.keep_menu_open = true
    end
    local menu = ListMenu.create(menu_options)
    if menu.title_bar then
        menu.title_bar.show_parent = home
    end
    menu.show_parent = home
    return menu
end

local function buildDownloadsMenu(bottom_bar, home)
    local menu_options = {
        title = nil,
        grid = false,
        item_table = DownloadsUI.buildDownloadsMenuTable({}, {}),
        custom_title_bar = SuwayomiStatusBar:new{
            left_text = "Downloads",
            right_text = " ",
        },
        footer_widget = bottom_bar,
    }
    local menu = ListMenu.create(menu_options)
    if menu.title_bar then
        menu.title_bar.show_parent = home
    end
    menu.show_parent = home
    return menu
end

local function buildSettingsMenu(bottom_bar, home)
    local menu_options = {
        title = nil,
        grid = false,
        item_table = {
            {
                text = "Settings screen is not yet wired",
                select_enabled = false,
            },
        },
        custom_title_bar = SuwayomiStatusBar:new{
            left_text = "Settings",
            right_text = " ",
        },
        footer_widget = bottom_bar,
    }
    local menu = ListMenu.create(menu_options)
    if menu.title_bar then
        menu.title_bar.show_parent = home
    end
    menu.show_parent = home
    return menu
end

local function defaultBottomActions(home_ref)
    return {
        { text = "Library",   action = function() home_ref.home:showTab("library") end },
        { text = "Downloads", action = function() home_ref.home:showTab("downloads") end },
        { text = "Settings",  action = function() home_ref.home:showTab("settings") end },
        { text = "Close",     action = function() UIManager:close(home_ref.home) end },
    }
end

local function attachMenuToHome(menu, bottom_bar, home)
    if not menu or not home then
        return
    end
    if menu.footer then
        menu.footer[1] = bottom_bar
        menu._suwayomi_footer_widget = bottom_bar
    end
    menu.show_parent = home
    if menu.title_bar then
        menu.title_bar.show_parent = home
    end
    home[1] = menu
    home.menu = menu
    home.dimen = menu.dimen
end

function SuwayomiHome.show(manga_list, onSelectCallback, options)
    options = options or {}
    local home_ref = { home = nil }
    local bottom_actions = options.bottom_actions or defaultBottomActions(home_ref)
    local bottom_bar = SuwayomiBottomBar:new{
        buttons = bottom_actions,
    }

    local home = SuwayomiHomeWidget:new{ menu = nil }
    home_ref.home = home
    home._suwayomi_bottom_bar = bottom_bar
    home.tabs = {}

    local library_menu = buildLibraryMenu(
        manga_list,
        onSelectCallback,
        bottom_bar,
        home
    )
    home.tabs.library = library_menu

    home.showTab = function(self, tab_id)
        if self.menu then
            if self.menu._suwayomi_status_update then
                UIManager:unschedule(self.menu._suwayomi_status_update)
                self.menu._suwayomi_status_update = nil
            end
            ListMenu.cancelThumbnailJobs(self.menu)
        end

        local menu = self.tabs[tab_id]
        if not menu then
            if tab_id == "downloads" then
                menu = buildDownloadsMenu(self._suwayomi_bottom_bar, self)
                self.tabs.downloads = menu
            elseif tab_id == "settings" then
                menu = buildSettingsMenu(self._suwayomi_bottom_bar, self)
                self.tabs.settings = menu
            end
        end

        if not menu then
            return
        end

        attachMenuToHome(menu, self._suwayomi_bottom_bar, self)

        if tab_id == "library" then
            scheduleStatusRefresh(menu)
        end

        if UIManager._window_stack then
            UIManager:setDirty(self, "ui")
        end
    end

    attachMenuToHome(library_menu, bottom_bar, home)

    UIManager:show(home)
    scheduleStatusRefresh(library_menu)
    return library_menu
end

return SuwayomiHome
