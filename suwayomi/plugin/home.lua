-- Boundary: HomeController.
--
-- Responsibility: Owns the plugin home dialog, main-menu entry, and generic KOReader message/loading helpers.
-- Owned state: Plugin UI state only; it does not own persisted settings or network state.
-- Dependencies: KOReader UI helpers, Suwayomi runtime modules, and the plugin i18n facade are required at module load to match the original plugin runtime.
-- External data: callers must continue to treat API responses, settings values, worker files, and filesystem paths as untrusted until checked locally.

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local SuwayomiUI = require("suwayomi/ui")
local I18n = require("suwayomi/i18n")
local FullSync = require("suwayomi/offline/full_sync")

local HomeController = {}
HomeController.__index = HomeController
local READER_RETURN_MENU_ID = "suwayomi_reader_return"

-- Controllers expose new(deps) for a consistent boundary; methods remain plugin-bound mixins so this refactor can move code without changing callback behavior.
function HomeController:new(deps)
    deps = deps or {}
    return setmetatable({
        plugin = deps.plugin,
    }, self)
end

local Methods = {}

local function ensureReaderReturnMenuOrder()
    local ok, reader_menu_order = pcall(require, "ui/elements/reader_menu_order")
    local main_order = ok and reader_menu_order and reader_menu_order.main or nil
    if type(main_order) ~= "table" then
        return
    end
    for _, item_id in ipairs(main_order) do
        if item_id == READER_RETURN_MENU_ID then
            return
        end
    end
    table.insert(main_order, 1, READER_RETURN_MENU_ID)
end

function Methods:showNotImplemented(message)
    self:showMessage(message)
end


function Methods:showTopLevelScreen(route_id, callback)
    local widget = callback()
    if widget and self.trackSuwayomiScreen then
        self:trackSuwayomiScreen(route_id, widget)
    end
    return widget
end


function Methods:buildHomeActions()
    return {
        {
            id = "library",
            text = I18n.t("Library"),
            callback = function()
                if self.needsOnboardingSetup and self:needsOnboardingSetup() then
                    self:showOnboardingSetup({ first_run = true })
                    return
                end
                return self:showTopLevelScreen("library", function()
                    return self:showLibrary()
                end)
            end,
        },
        {
            id = "browse",
            text = I18n.t("Browse"),
            callback = function()
                return self:showTopLevelScreen("browse", function()
                    return self:browseSuwayomi()
                end)
            end,
        },
        {
            id = "downloads",
            text = I18n.t("Downloads"),
            callback = function()
                return self:showTopLevelScreen("downloads", function()
                    return self:showDownloads()
                end)
            end,
        },
        {
            id = "sync",
            text = I18n.t("Sync"),
            enabled_func = function()
                return not FullSync:isRunning()
            end,
            callback = function()
                if FullSync:isRunning() then
                    self:showMessage(I18n.t("A full sync is already in progress."))
                    return
                end
                FullSync:start(nil, function(result)
                    if result and not result.ok then
                        self:showMessage(I18n.f("Sync failed: %1", result.error or I18n.t("unknown error")))
                    end
                end)
            end,
        },
        {
            id = "settings",
            text = I18n.t("Settings"),
            callback = function()
                return self:showTopLevelScreen("settings", function()
                    return self:showSettings()
                end)
            end,
        },
        {
            id = "close",
            text = I18n.t("Close plugin"),
            close_before_select = false,
            callback = function()
                if self.closeSuwayomiPlugin then
                    self:closeSuwayomiPlugin()
                end
            end,
        },
    }
end


function Methods:buildMenuActions()
    return {
        {
            id = "open",
            text_func = function()
                return self:_isSuwayomiShowing() and I18n.t("Close") or I18n.t("Open")
            end,
            callback = function()
                if self:_isSuwayomiShowing() then
                    UIManager:nextTick(function()
                        if self.closeSuwayomiPlugin then
                            self:closeSuwayomiPlugin()
                        end
                    end)
                    return
                end
                if self.needsOnboardingSetup and self:needsOnboardingSetup() then
                    self:showOnboardingSetup({ first_run = true })
                    return
                end
                return self:showTopLevelScreen("library", function()
                    return self:showLibrary()
                end)
            end,
        },
        {
            id = "sync",
            text = I18n.t("Sync"),
            enabled_func = function()
                return not FullSync:isRunning()
            end,
            callback = function()
                if FullSync:isRunning() then
                    self:showMessage(I18n.t("A full sync is already in progress."))
                    return
                end
                FullSync:start(nil, function(result)
                    if result and not result.ok then
                        self:showMessage(I18n.f("Sync failed: %1", result.error or I18n.t("unknown error")))
                    end
                end)
            end,
        },
        {
            id = "settings",
            text = I18n.t("Settings"),
            callback = function()
                return self:showTopLevelScreen("settings", function()
                    return self:showSettings()
                end)
            end,
        },
    }
end


function Methods:showHome()
    local dialog = SuwayomiUI.showHomeDialog({
        actions = self:buildHomeActions(),
        onClose = function()
            if self.suwayomi_navigation then
                self.suwayomi_navigation:pop(self.suwayomi_home_menu)
            end
        end,
    }, function(action)
        if action and action.callback then
            action.callback()
        end
    end)
    self.suwayomi_home_menu = dialog
    if dialog and self.trackSuwayomiScreen then
        self:trackSuwayomiScreen("home", dialog)
    end
    return dialog
end


function Methods:_extendMenuOrder()
    local ok, order = pcall(require, "ui/elements/filemanager_menu_order")
    if not ok or type(order) ~= "table"
            or type(order["KOMenu:menu_buttons"]) ~= "table" then
        return
    end
    for _, id in ipairs(order["KOMenu:menu_buttons"]) do
        if id == "suwayomi_tab" then
            return
        end
    end
    table.insert(order["KOMenu:menu_buttons"], 2, "suwayomi_tab")
    order.suwayomi_tab = {}
end


function Methods:_registerStartWithMenu()
    local plugin = self
    local ok, FMMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if not ok or not FMMenu then
        return
    end
    local orig_fn = FMMenu.getStartWithMenuTable
    if type(orig_fn) ~= "function" then
        return
    end
    if FMMenu._suwayomi_patched then
        return
    end
    FMMenu._suwayomi_patched = true

    FMMenu.getStartWithMenuTable = function(self_fm)
        local result = orig_fn(self_fm)
        if type(result) ~= "table" or type(result.sub_item_table) ~= "table" then
            return result
        end

        local already
        for _, entry in ipairs(result.sub_item_table) do
            if entry.text == I18n.t("Suwayomi") then
                already = true
                break
            end
        end
        if not already then
            table.insert(result.sub_item_table, {
                text = I18n.t("Suwayomi"),
                radio = true,
                checked_func = function()
                    return _G.G_reader_settings
                            and _G.G_reader_settings:readSetting("start_with") == "suwayomi"
                end,
                callback = function()
                    if _G.G_reader_settings then
                        _G.G_reader_settings:saveSetting("start_with", "suwayomi")
                        _G.G_reader_settings:flush()
                    end
                    if plugin._isSuwayomiShowing and not plugin:_isSuwayomiShowing() then
                        if plugin.needsOnboardingSetup and plugin:needsOnboardingSetup() then
                            plugin:showOnboardingSetup({ first_run = true })
                        else
                            plugin:showLibrary()
                        end
                    end
                end,
            })
        end

        local orig_text_func = result.text_func
        result.text_func = function()
            if _G.G_reader_settings
                    and _G.G_reader_settings:readSetting("start_with") == "suwayomi" then
                return I18n.f("Start with: %1", I18n.t("Suwayomi"))
            end
            return orig_text_func and orig_text_func() or ""
        end
        return result
    end
end


function Methods:_isSuwayomiShowing()
    if not self.suwayomi_navigation then
        return false
    end
    return #self.suwayomi_navigation.entries > 0
end


function Methods:showLibrary()
    return self:getClient():showLibrary()
end


function Methods:closeMenu(menu)
    if menu and UIManager.close then
        UIManager:close(menu)
    end
end


function Methods:showMessage(message, options)
    local message_str = tostring(message or "")
    if message_str == "" then
        return
    end
    options = options or {}
    options.timeout = options.timeout or 2
    if SuwayomiUI and SuwayomiUI.showSnack then
        SuwayomiUI.showSnack(message_str, options)
    else
        UIManager:show(InfoMessage:new{
            text = message_str,
            timeout = options.timeout,
        })
    end
end


function Methods:withLoadingMessage(key, message, callback)
    if not message or tostring(message) == "" then
        return nil
    end
    self.loading_operations = self.loading_operations or {}
    if self.loading_operations[key] then
        return nil
    end

    self.loading_operations[key] = true
    local loading_message = InfoMessage:new{
        text = message,
        suwayomi_loading = true,
    }
    UIManager:show(loading_message)
    if UIManager.forceRePaint then
        UIManager:forceRePaint()
    end

    local results = { pcall(callback) }
    local ok = table.remove(results, 1)

    if UIManager.close then
        UIManager:close(loading_message)
    end
    self.loading_operations[key] = nil

    if not ok then
        error(results[1])
    end
    return unpack(results)
end


function Methods:showLoadingMessage(message)
    if not message or tostring(message) == "" then
        return nil
    end
    local loading_message = InfoMessage:new{
        text = message,
        suwayomi_loading = true,
    }
    UIManager:show(loading_message)
    if UIManager.forceRePaint then
        UIManager:forceRePaint()
    end
    return loading_message
end


function Methods:closeLoadingMessage(loading_message)
    if loading_message and UIManager.close then
        UIManager:close(loading_message)
    end
end


function Methods:addToMainMenu(menu_items)
    if self:isBookMode() then
        local context = self.getCurrentReaderReturnContext and self:getCurrentReaderReturnContext() or nil
        if context then
            ensureReaderReturnMenuOrder()
            menu_items[READER_RETURN_MENU_ID] = {
                text = I18n.t("Go to Suwayomi"),
                sorting_hint = "main",
                callback = function()
                    self:returnToSuwayomiChapters()
                end,
            }
        end
        return
    end

    menu_items.suwayomi_tab = { icon = "appbar.pokeball" }

    local suwayomi_tab_order = {}
    for _, action in ipairs(self:buildMenuActions()) do
        local menu_id = "suwayomi_" .. action.id
        table.insert(suwayomi_tab_order, menu_id)
        menu_items[menu_id] = {
            text = action.text,
            text_func = action.text_func,
            sorting_hint = "suwayomi_tab",
            enabled = action.enabled,
            enabled_func = action.enabled_func,
            callback = action.callback,
        }
    end

    local ok, order = pcall(require, "ui/elements/filemanager_menu_order")
    if ok and order and type(order.suwayomi_tab) == "table" then
        order.suwayomi_tab = suwayomi_tab_order
    end
end


HomeController.methods = Methods

return HomeController
