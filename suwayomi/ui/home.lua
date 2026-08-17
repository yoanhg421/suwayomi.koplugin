-- Boundary: Suwayomi home screen presentation.
--
-- Responsibility: build and show the full-screen Suwayomi home widget with a
-- tabbed bottom bar (Library, Recent, Updates, Downloads) where each tab
-- renders its own ListMenu inside the home container.
-- Owned state: status refresh scheduling and the per-tab menu cache.
-- Dependencies: ListMenu, ListRows, DownloadsUI, SuwayomiStatusBar,
--               SuwayomiBottomBar, SuwayomiFooter, SuwayomiHomeWidget,
--               UIManager, Device, package.

local UIManager = require("ui/uimanager")
local Device    = require("device")

local ListMenu       = require("suwayomi/ui/list_menu")
local ListRows       = require("suwayomi/ui/list_rows")
local DownloadsUI    = require("suwayomi/ui/downloads")
local SuwayomiOfflineStore = require("suwayomi/offline/store")
local SuwayomiStatusBar = require("suwayomi/ui/status_bar")
local SuwayomiBottomBar = require("suwayomi/ui/bottom_bar")
local SuwayomiFooter = require("suwayomi/ui/footer")
local SuwayomiHomeWidget = require("suwayomi/ui/home_widget")

local SuwayomiHome = {}

local function pluginIconDir()
    local ok, path = pcall(package.searchpath, "suwayomi/ui/home", package.path)
    if ok and path then
        return path:gsub("suwayomi/ui/home%.lua$", "suwayomi/icons/")
    end
    return "suwayomi/icons/"
end

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

local function scheduleSyncRefresh(menu, interval)
    if menu._suwayomi_sync_update then
        UIManager:unschedule(menu._suwayomi_sync_update)
    end
    interval = tonumber(interval) or 2
    menu._suwayomi_sync_update = function()
        if not menu or not menu.show_parent then
            menu._suwayomi_sync_update = nil
            return
        end
        local active = false
        local stack = UIManager._window_stack
        if type(stack) == "table" then
            for _, win in ipairs(stack) do
                if win.widget == menu.show_parent then
                    active = true
                    break
                end
            end
        end
        if not active then
            menu._suwayomi_sync_update = nil
            return
        end
        if menu.title_bar and menu.title_bar.updateSyncIcon then
            pcall(function()
                menu.title_bar:updateSyncIcon()
            end)
        end
        UIManager:scheduleIn(interval, menu._suwayomi_sync_update)
    end
    UIManager:scheduleIn(interval, menu._suwayomi_sync_update)
end

local function onPageChanged(menu)
    if menu._suwayomi_footer_widget and menu._suwayomi_footer_widget.updatePage then
        menu._suwayomi_footer_widget:updatePage(menu.page, menu.page_num)
    end
end

local function buildFooter(bottom_bar, home)
    local footer = SuwayomiFooter:new{
        bottom_bar = bottom_bar,
    }
    footer.show_parent = home
    footer.page_indicator.show_parent = home
    footer.bottom_bar.show_parent = home
    return footer
end

local function buildLibraryMenu(manga_list, onSelectCallback, bottom_bar, home, options)
    options = options or {}
    local left, right = buildStatusStrings()
    local footer = buildFooter(bottom_bar, home)
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
        footer_widget = footer,
        thumbnail_credentials = options.thumbnail_credentials,
        on_page_changed = onPageChanged,
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

local function buildDownloadsMenu(bottom_bar, home, snapshot)
    local left, right = buildStatusStrings()
    local callbacks = home._suwayomi_downloads_callbacks or {}
    local footer = buildFooter(bottom_bar, home)
    local menu_options = {
        title = nil,
        grid = false,
        item_table = DownloadsUI.buildDownloadsMenuTable(
            snapshot or {},
            callbacks,
            { download_directory_summary = home._suwayomi_download_directory_summary }
        ),
        custom_title_bar = SuwayomiStatusBar:new{
            left_text = left,
            right_text = right,
        },
        footer_widget = footer,
        on_page_changed = onPageChanged,
    }
    local menu = ListMenu.create(menu_options)
    if menu.title_bar then
        menu.title_bar.show_parent = home
    end
    menu.show_parent = home
    return menu
end

local function buildRecentMenu(onSelectCallback, bottom_bar, home, options)
    options = options or {}
    local left, right = buildStatusStrings()
    local footer = buildFooter(bottom_bar, home)
    local chapter_history = SuwayomiOfflineStore:getChapterHistory()
    local manga_map = SuwayomiOfflineStore:getMangaMap()
    local recent_manga = {}
    local seen = {}
    for _, entry in ipairs(chapter_history or {}) do
        local manga = entry.manga
        if manga and not seen[tostring(manga.id)] then
            seen[tostring(manga.id)] = true
            local full_manga = manga_map and manga_map[tostring(manga.id)] or manga
            table.insert(recent_manga, full_manga)
        end
    end
    local item_table
    if #recent_manga == 0 then
        item_table = {
            { text = "No recent chapters", select_enabled = false },
        }
    else
        item_table = ListRows.buildMangaMenuTable(recent_manga, {
            show_in_library = false,
            on_select = onSelectCallback,
        })
    end
    local menu_options = {
        title = nil,
        grid = true,
        item_table = item_table,
        custom_title_bar = SuwayomiStatusBar:new{
            left_text = left,
            right_text = right,
        },
        footer_widget = footer,
        thumbnail_credentials = options.thumbnail_credentials,
        on_page_changed = onPageChanged,
    }
    for _, item in ipairs(menu_options.item_table) do
        item.keep_menu_open = true
    end
    local menu = ListMenu.create(menu_options)
    if menu and menu.perpage and #menu.item_table > menu.perpage then
        for i = #menu.item_table, menu.perpage + 1, -1 do
            table.remove(menu.item_table, i)
        end
        if menu.updateItems then
            menu:updateItems()
        end
    end
    if menu.title_bar then
        menu.title_bar.show_parent = home
    end
    menu.show_parent = home
    return menu
end

local function buildUpdatesMenu(bottom_bar, home)
    local left, right = buildStatusStrings()
    local footer = buildFooter(bottom_bar, home)
    local menu_options = {
        title = nil,
        grid = false,
        item_table = {
            { text = "Updates not yet wired", select_enabled = false },
        },
        custom_title_bar = SuwayomiStatusBar:new{
            left_text = left,
            right_text = right,
        },
        footer_widget = footer,
        on_page_changed = onPageChanged,
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
        { text = "Library",   icon = "book.svg", action = function() home_ref.home:showTab("library") end },
        { text = "Recent",    icon = "clock-counter-clockwise.svg", action = function() home_ref.home:showTab("recent") end },
        { text = "Updates",   icon = "arrows-clockwise.svg", action = function() home_ref.home:showTab("updates") end },
        { text = "Downloads", icon = "download.svg", action = function() home_ref.home:showTab("downloads") end },
    }
end

local function attachMenuToHome(menu, _bottom_bar, home)
    if not menu or not home then
        return
    end
    if menu.footer then
        menu.footer[1] = menu._suwayomi_footer_widget
        menu._suwayomi_footer_widget:updatePage(menu.page, menu.page_num)
    end
    menu.show_parent = home
    if menu.title_bar then
        menu.title_bar.show_parent = home
        pcall(function()
            menu.title_bar:updateSyncIcon()
        end)
    end
    home[1] = menu
    home.menu = menu
    home.dimen = menu.dimen
end

function SuwayomiHome.show(manga_list, onSelectCallback, options)
    options = options or {}
    local home_ref = { home = nil }
    local bottom_actions = options.bottom_actions or defaultBottomActions(home_ref)
    local icon_dir = options.icon_dir or pluginIconDir()
    local bottom_bar = SuwayomiBottomBar:new{
        buttons = bottom_actions,
        icon_dir = icon_dir,
    }

    local home = SuwayomiHomeWidget:new{ menu = nil }
    home_ref.home = home
    home._suwayomi_bottom_bar = bottom_bar
    home._suwayomi_on_select = onSelectCallback
    home._suwayomi_home_options = options
    home._suwayomi_get_downloads_snapshot = options.getDownloadsSnapshot
    home._suwayomi_downloads_callbacks = options.downloads_callbacks
    home._suwayomi_download_directory_summary = options.download_directory_summary
    home.tabs = {}

    local library_menu = buildLibraryMenu(
        manga_list,
        onSelectCallback,
        bottom_bar,
        home,
        options
    )
    home.tabs.library = library_menu

    home._suwayomi_current_tab = "library"
    home.showTab = function(self, tab_id)
        self._suwayomi_current_tab = tab_id
        if self.menu then
            if self.menu._suwayomi_status_update then
                UIManager:unschedule(self.menu._suwayomi_status_update)
                self.menu._suwayomi_status_update = nil
            end
            if self.menu._suwayomi_sync_update then
                UIManager:unschedule(self.menu._suwayomi_sync_update)
                self.menu._suwayomi_sync_update = nil
            end
            ListMenu.cancelThumbnailJobs(self.menu)
        end

        local menu
        if tab_id == "library" then
            menu = self.tabs.library
        elseif tab_id == "downloads" then
            local snapshot = self._suwayomi_get_downloads_snapshot
                and self._suwayomi_get_downloads_snapshot()
                or {}
            menu = buildDownloadsMenu(self._suwayomi_bottom_bar, self, snapshot)
            self.tabs.downloads = menu
        elseif tab_id == "recent" then
            menu = self.tabs.recent or buildRecentMenu(self._suwayomi_on_select, self._suwayomi_bottom_bar, self, self._suwayomi_home_options)
            self.tabs.recent = menu
        elseif tab_id == "updates" then
            menu = self.tabs.updates or buildUpdatesMenu(self._suwayomi_bottom_bar, self)
            self.tabs.updates = menu
        end

        if not menu then
            return
        end

        attachMenuToHome(menu, self._suwayomi_bottom_bar, self)

        scheduleStatusRefresh(menu)
        scheduleSyncRefresh(menu)

        if UIManager._window_stack then
            UIManager:setDirty(self, "ui")
        end
    end

    attachMenuToHome(library_menu, bottom_bar, home)

    home._suwayomi_reopen = function()
        local saved_tab = home._suwayomi_current_tab or "library"
        local new_menu = SuwayomiHome.show(manga_list, onSelectCallback, options)
        if new_menu and new_menu.show_parent and saved_tab ~= "library" then
            local new_home = new_menu.show_parent
            UIManager:nextTick(function()
                new_home:showTab(saved_tab)
            end)
        end
    end

    UIManager:show(home)
    scheduleStatusRefresh(library_menu)
    scheduleSyncRefresh(library_menu)
    return library_menu
end

return SuwayomiHome
