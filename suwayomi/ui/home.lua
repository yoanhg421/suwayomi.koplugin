-- Boundary: Suwayomi home screen presentation.
--
-- Responsibility: build and show the full-screen Suwayomi home widget, which
-- wraps the grid menu with a custom status bar and bottom tab bar.
-- Owned state: status refresh scheduling.
-- Dependencies: ListMenu, SuwayomiStatusBar, SuwayomiBottomBar,
--               SuwayomiHomeWidget, KOReader UIManager and Device.

local UIManager = require("ui/uimanager")
local Device    = require("device")

local ListMenu       = require("suwayomi/ui/list_menu")
local ListRows       = require("suwayomi/ui/list_rows")
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

local function defaultBottomActions(home_ref)
    return {
        { text = "Library",  action = function() end },
        { text = "Browse",   action = function() end },
        { text = "Downloads", action = function() end },
        { text = "Sync",     action = function() end },
        { text = "Settings", action = function() end },
        { text = "Close",    action = function() UIManager:close(home_ref.home) end },
    }
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

    local home_ref = { home = nil }
    local bottom_actions = options.bottom_actions or defaultBottomActions(home_ref)
    local bottom_bar = SuwayomiBottomBar:new{
        buttons = bottom_actions,
    }
    options.footer_widget = bottom_bar

    local menu = ListMenu.create(options)
    if menu.title_bar then
        menu.title_bar.show_parent = menu
    end

    local home = SuwayomiHomeWidget:new{ menu = menu }
    home_ref.home = home

    menu.show_parent = home
    if menu.title_bar then
        menu.title_bar.show_parent = home
    end
    bottom_bar.show_parent = home

    UIManager:show(home)
    scheduleStatusRefresh(menu)
    return menu
end

return SuwayomiHome
