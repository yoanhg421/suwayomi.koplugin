-- Boundary: full sync controller.
--
-- Responsibility: start a background worker that fetches chapters and covers for
-- the whole library and persists them to the offline store.
-- Owned state: none.
-- Dependencies: subprocess job, full sync worker, settings, offline store.
-- External data: the result is reported through on_finish callbacks.

local SubprocessJob = require("suwayomi/subprocess/job")
local FullSyncWorker = require("suwayomi/offline/full_sync_worker")
local SuwayomiSettings = require("suwayomi/settings")
local SuwayomiOfflineStore = require("suwayomi/offline/store")
local FFIUtil = require("ffi/util")
local UIManager = require("ui/uimanager")

local FullSync = {
    _running = false,
}

function FullSync:isRunning()
    return self._running == true
end

function FullSync:_setRunning(running)
    self._running = running == true
end

function FullSync:start(manga_list, on_finish)
    if self:isRunning() then
        if on_finish then
            on_finish({ ok = false, error = "A full sync is already in progress." })
        end
        return false
    end

    local credentials = SuwayomiSettings:load()
    if not credentials.server_url or credentials.server_url == "" then
        if on_finish then
            on_finish({ ok = false, error = "Missing Suwayomi server URL." })
        end
        return false
    end

    self:_setRunning(true)
    local active = SubprocessJob.start({
        active = {
            credentials = credentials,
            manga_list = manga_list or {},
        },
        ffi_util = FFIUtil,
        ui_manager = UIManager,
        prefix = "full_sync",
        poll_interval_seconds = 0.5,
        run = function(result_path, inner_active)
            FullSyncWorker:run(inner_active.credentials, inner_active.manga_list, result_path)
        end,
        read_result = function(result_path)
            return FullSyncWorker:readResult(result_path)
        end,
        on_finish = function(_, result)
            self:_setRunning(false)
            SuwayomiOfflineStore:reset()
            if on_finish then
                on_finish(result or { ok = false, error = "Full sync did not report a result." })
            end
        end,
        on_timeout = function()
            self:_setRunning(false)
            SuwayomiOfflineStore:reset()
            if on_finish then
                on_finish({ ok = false, error = "Full sync timed out." })
            end
        end,
        on_error = function(err)
            self:_setRunning(false)
            SuwayomiOfflineStore:reset()
            if on_finish then
                on_finish({ ok = false, error = err or "Could not start full sync." })
            end
        end,
    })
    return active ~= nil
end

return FullSync
