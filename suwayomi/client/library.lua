-- Boundary: library flow.
--
-- Responsibility: load library pages, apply category filtering, and route selected library manga actions.
-- Owned state: installed methods only; runtime state remains on SuwayomiClient instances.
-- Dependencies: SuwayomiClient core helpers and injected runtime services.
-- External data: validated by the moved methods before UI rendering or worker use.

local M = {}
local I18n = require("suwayomi/i18n")
local SuwayomiOfflineStore = require("suwayomi/offline/store")
local SuwayomiOfflineSync = require("suwayomi/offline/sync")
local FullSync = require("suwayomi/offline/full_sync")

function M.install(SuwayomiClient)
function SuwayomiClient:mangaBelongsToCategory(manga, category)
    if not category or not category.id then
        return true
    end
    for _index, candidate in ipairs(manga.categories or {}) do
        if tostring(candidate.id) == tostring(category.id) then
            return true
        end
    end
    return false
end

function SuwayomiClient:filterLibraryMangaByCategory(manga_list, category)
    if not category or not category.id then
        return manga_list or {}
    end

    local filtered = {}
    for _index, manga in ipairs(manga_list or {}) do
        if self:mangaBelongsToCategory(manga, category) then
            table.insert(filtered, manga)
        end
    end
    return filtered
end

function SuwayomiClient:buildLibraryCategoryChoices(categories)
    local choices = {
        {
            id = nil,
            name = I18n.t("All manga"),
        },
    }
    for _index, category in ipairs(categories or {}) do
        table.insert(choices, category)
    end
    return choices
end

local function libraryTimeoutMessage()
    return I18n.t("Library loading timed out. Check your connection, then open Library again.")
end

function SuwayomiClient:startLibraryNetworkRequest(credentials, request, loading_message, on_finish)
    local active_requests = self.active_library_network_requests or {}
    self.active_library_network_requests = active_requests
    local slot_key = tostring(request and request.action or "library_request")
    local previous = active_requests[slot_key]
    local request_job = self:getNetworkRequestJob()
    if previous and previous.active and request_job.cancel then
        request_job.cancel(previous.active)
    end

    local request_token = {}
    active_requests[slot_key] = request_token
    local ok, active, start_err = pcall(request_job.start, {
        owner = self.plugin,
        credentials = credentials,
        request = request,
        loading_message = loading_message,
        result_prefix = "library_request",
        timeout_seconds = self:getNetworkRequestTimeoutSeconds(),
        timeout_message = libraryTimeoutMessage(),
        on_cancel = function()
            if active_requests[slot_key] == request_token then
                active_requests[slot_key] = nil
            end
        end,
        on_finish = function(result)
            if active_requests[slot_key] ~= request_token then
                return
            end
            active_requests[slot_key] = nil
            if on_finish then
                on_finish(result)
            end
        end,
    })
    if not ok then
        start_err = active
        active = nil
    end
    if not active then
        if active_requests[slot_key] == request_token then
            active_requests[slot_key] = nil
        end
        return false, start_err
    end
    if active_requests[slot_key] == request_token then
        request_token.active = active
    end
    return true
end

function SuwayomiClient:cancelLibraryNetworkRequests()
    local active_requests = self.active_library_network_requests
    if not active_requests then
        return
    end

    local request_job = self:getNetworkRequestJob()
    for slot_key, request_token in pairs(active_requests) do
        active_requests[slot_key] = nil
        if request_token.active and request_job.cancel then
            request_job.cancel(request_token.active)
        end
    end
    self.active_library_network_requests = nil
end

function SuwayomiClient:showLibraryMangaResult(category, credentials, result)
    if not result or not result.ok then
        local offline_manga = SuwayomiOfflineStore:getMangaList()
        local manga = self:filterLibraryMangaByCategory(offline_manga, category)
        if #manga > 0 then
            result = { ok = true, manga = manga, total_count = #manga }
        else
            self.plugin:showMessage(result and result.error or I18n.t("Could not load Suwayomi library."))
            return
        end
    end

    local manga = self:filterLibraryMangaByCategory(result.manga or {}, category)
    self:log({
        operation = "showLibrary",
        event = "library_manga_loaded",
        category_id = category and category.id,
        manga_count = #manga,
        total_count = result.total_count,
    })

    local library_manga = manga
    local hub_actions = {}
    if self.plugin.buildHomeActions then
        for _, action in ipairs(self.plugin:buildHomeActions()) do
            if action.id ~= "library" then
                table.insert(hub_actions, action)
            end
        end
    end
    local menu_options = self:getTitleBarMenuOptions({
        title = I18n.t("Suwayomi Library"),
        actions = hub_actions,
        hide_home = true,
        onSelect = function(action)
            if action and action.callback then
                action.callback()
                return true
            end
            return false
        end,
    }) or {}
    menu_options.thumbnail_credentials = credentials
    local library_menu
    local pending_library_menu_refresh = false
    local function refreshLibraryMangaMenu()
        for index = #library_manga, 1, -1 do
            if type(library_manga[index]) == "table" and library_manga[index].in_library == false then
                table.remove(library_manga, index)
            end
        end
        if not library_menu or not library_menu._suwayomi_menu then
            pending_library_menu_refresh = true
            return
        end
        if self.ui.updateLibraryMangaMenu then
            self.ui.updateLibraryMangaMenu(library_menu._suwayomi_menu, library_manga, function(selected_manga)
                if self.plugin.showMangaActions then
                    self.plugin:showMangaActions(selected_manga, {
                        onMangaUpdated = refreshLibraryMangaMenu,
                    })
                else
                    self.plugin:showChaptersForManga(selected_manga)
                end
            end, menu_options)
        end
    end

    library_menu = self.ui.showSuwayomiHome(library_manga, function(selected_manga)
        if self.plugin.showMangaActions then
            self.plugin:showMangaActions(selected_manga, {
                onMangaUpdated = refreshLibraryMangaMenu,
            })
        else
            self.plugin:showChaptersForManga(selected_manga)
        end
    end, menu_options)
    self:trackScreen("library", library_menu)
    if pending_library_menu_refresh then
        refreshLibraryMangaMenu()
    end
end

function SuwayomiClient:showLibraryManga(category, credentials)
    credentials = credentials or self.settings:load()
    local offline_manga = SuwayomiOfflineStore:getMangaList()
    local showed_offline = false
    if #offline_manga > 0 then
        self:showLibraryMangaResult(category, credentials, {
            ok = true,
            manga = offline_manga,
            total_count = #offline_manga,
            from_offline = true,
        })
        showed_offline = true
    end
    if not credentials.server_url or credentials.server_url == "" then
        if not showed_offline then
            self:showLibraryMangaResult(category, credentials, nil)
        end
        return true
    end
    local started, err = self:startLibraryNetworkRequest(credentials, {
        action = "fetch_library_manga_pages",
    }, nil, function(result)
        if result and result.ok and result.manga and #result.manga > 0 then
            if not FullSync:isRunning() then
                local sync_snack
                if self.ui and self.ui.showSnack then
                    sync_snack = self.ui.showSnack(I18n.t("Syncing..."))
                end
                FullSync:start(result.manga, function(sync_result)
                    if self.ui and self.ui.closeSnack then
                        self.ui.closeSnack(sync_snack)
                    end
                    if self.ui and self.ui.showSnack then
                        if sync_result and sync_result.ok then
                            self.ui.showSnack(I18n.f("Library sync complete. %1 manga updated.", tostring(sync_result.synced or 0)), { timeout = 2 })
                        else
                            self.ui.showSnack(I18n.f("Library sync failed: %1", sync_result and sync_result.error or I18n.t("unknown error")), { timeout = 3 })
                        end
                    end
                end)
            end
        end
        if not showed_offline then
            self:showLibraryMangaResult(category, credentials, result)
        end
    end)
    if not started and not showed_offline then
        self.plugin:showMessage(I18n.f("Could not start library loading: %1", err or I18n.t("unknown error")))
    end
    return started or showed_offline
end

function SuwayomiClient:showLibraryCategoriesResult(credentials, result)
    if result and result.ok and not result.from_offline then
        SuwayomiOfflineSync:syncCategories(result.categories)
    end

    if not result or not result.ok then
        local offline_categories = SuwayomiOfflineStore:getCategories()
        if #offline_categories > 0 then
            result = { ok = true, categories = offline_categories }
        else
            self.plugin:showMessage(result and result.error or I18n.t("Could not load Suwayomi library."))
            return
        end
    end

    local categories = result.categories or {}
    local picker_behavior = self.settings.loadLibraryCategoryPickerBehavior
        and self.settings:loadLibraryCategoryPickerBehavior()
        or "automatic"
    local should_show_category_picker = picker_behavior == "always"
        or (picker_behavior == "automatic" and #categories > 1)

    if should_show_category_picker and #categories > 0 then
        local category_menu = self.ui.showLibraryCategoryMenu(self:buildLibraryCategoryChoices(categories), function(category)
            self:showLibraryManga(category, credentials)
        end, self:getTitleBarMenuOptions({
            title = I18n.t("Suwayomi Library"),
        }))
        self:trackScreen("library-categories", category_menu)
        return
    end

    self:showLibraryManga(nil, credentials)
end

function SuwayomiClient:showLibrary()
    return self:time("showLibrary", {}, function()
        local credentials = self.settings:load()
        local offline_categories = SuwayomiOfflineStore:getCategories()
        local showed_offline = false
        if #offline_categories > 0 then
            self:showLibraryCategoriesResult(credentials, {
                ok = true,
                categories = offline_categories,
                from_offline = true,
            })
            showed_offline = true
        end
        if not credentials.server_url or credentials.server_url == "" then
            if not showed_offline then
                if SuwayomiOfflineStore:getLastSyncTime() > 0 then
                    self:showLibraryCategoriesResult(credentials, nil)
                    return
                end
                self.plugin:showMessage(I18n.t("Set up your Suwayomi server login first."))
                if self.plugin.showOnboardingSetup then
                    self.plugin:showOnboardingSetup({ first_run = true })
                end
            end
            return
        end
        if self.plugin.schedulePendingReadSync then
            self.plugin:schedulePendingReadSync(credentials)
        end

        local started, err = self:startLibraryNetworkRequest(credentials, {
            action = "fetch_library_categories",
        }, nil, function(result)
            if result and result.ok and result.categories and #result.categories > 0 then
                SuwayomiOfflineSync:syncCategories(result.categories)
            end
            if not showed_offline then
                self:showLibraryCategoriesResult(credentials, result)
            end
        end)
        if not started and not showed_offline then
            self.plugin:showMessage(I18n.f("Could not start library loading: %1", err or I18n.t("unknown error")))
        end
        return started or showed_offline
    end)
end
end

return M
