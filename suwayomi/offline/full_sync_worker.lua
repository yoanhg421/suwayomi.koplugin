-- Boundary: full sync worker process.
--
-- Responsibility: fetch chapter lists and covers for every manga in the library
-- in a subprocess and persist them to the offline store.
-- Owned state: none.
-- Dependencies: dkjson, Suwayomi API facade, offline store and sync helpers.
-- External data: runs against the configured Suwayomi server.

local SuwayomiAPI = require("suwayomi/api")
local SuwayomiOfflineSync = require("suwayomi/offline/sync")
local SuwayomiOfflineStore = require("suwayomi/offline/store")
local ThumbnailWorker = require("suwayomi/ui/thumbnail_worker")
local ThumbnailCache = require("suwayomi/ui/thumbnail_cache")
local SubprocessJob = require("suwayomi/subprocess/job")

local FFIUtil = require("ffi/util")

local function yieldToUI()
    if FFIUtil and FFIUtil.usleep then
        pcall(FFIUtil.usleep, 5000)
    end
end

local FullSyncWorker = {}

function FullSyncWorker:writeResult(result_path, result)
    return SubprocessJob.writeResult(result_path, result)
end

function FullSyncWorker:readResult(result_path)
    return SubprocessJob.readResult(result_path, function(parsed)
        parsed.ok = parsed.ok == true
        parsed.synced = tonumber(parsed.synced) or 0
        parsed.skipped = tonumber(parsed.skipped) or 0
        return parsed
    end)
end

local function fetchMangaList(credentials)
    local ok, result = pcall(function()
        return SuwayomiAPI.fetchLibraryManga(credentials, {})
    end)
    if not ok then
        return nil, tostring(result)
    end
    if not result or not result.ok then
        return nil, result and result.error or "Could not fetch library manga."
    end
    return result.manga, nil
end

local function syncMangaChapters(credentials, manga)
    if not manga or not manga.id then
        return false
    end
    local ok, result = pcall(function()
        return SuwayomiAPI.fetchChaptersForManga(credentials, manga.id)
    end)
    if not ok or not result or not result.ok then
        return false
    end
    SuwayomiOfflineSync:syncChapters(manga.id, result)
    yieldToUI()
    return true
end

local COVER_CACHE_OPTIONS = {
    variant = "raw",
    width = 240,
    height = 360,
}

local function syncChapterHistory(credentials)
    if not credentials or credentials.server_url == "" then
        return
    end
    local ok, result = pcall(function()
        return SuwayomiAPI.fetchChapterHistory(credentials, { first = 50 })
    end)
    if not ok or not result or not result.ok then
        return
    end
    local seen = {}
    local recent_manga = {}
    for _, entry in ipairs(result.history or {}) do
        if entry and entry.manga and not seen[tostring(entry.manga.id)] then
            seen[tostring(entry.manga.id)] = true
            entry.manga._suwayomi_last_read_at = tonumber(entry.last_read_at) or 0
            table.insert(recent_manga, entry.manga)
        end
    end
    SuwayomiOfflineStore:setChapterHistory(result.history or {})
    SuwayomiOfflineStore:setRecentMangaList(recent_manga)
end

local function syncMangaCover(credentials, manga, previous)
    if not manga or not manga.thumbnail_url or manga.thumbnail_url == "" then
        return false
    end
    if previous and previous.thumbnail_url == manga.thumbnail_url
            and ThumbnailCache.find(credentials, manga.thumbnail_url, COVER_CACHE_OPTIONS) then
        return true
    end
    local result_path = SubprocessJob.buildResultPath("thumbnail")
    local ok, result = pcall(function()
        return ThumbnailWorker:run(credentials, manga.thumbnail_url, result_path, COVER_CACHE_OPTIONS)
    end)
    pcall(function()
        os.remove(result_path)
    end)
    if not ok or not result or not result.ok then
        return false
    end
    yieldToUI()
    return true
end

function FullSyncWorker:run(credentials, manga_list, result_path)
    local synced = 0
    local skipped = 0

    if not credentials or credentials.server_url == "" then
        return self:writeResult(result_path, {
            ok = false,
            error = "Missing Suwayomi server URL.",
            synced = synced,
            skipped = skipped,
        })
    end

    local previous_manga_map = SuwayomiOfflineStore:getMangaMap() or {}

    if type(manga_list) ~= "table" or #manga_list == 0 then
        local err
        manga_list, err = fetchMangaList(credentials)
        if not manga_list then
            return self:writeResult(result_path, {
                ok = false,
                error = err,
                synced = synced,
                skipped = skipped,
            })
        end
    end

    SuwayomiOfflineSync:syncLibraryManga({ manga = manga_list })
    syncChapterHistory(credentials)

    for _, manga in ipairs(manga_list or {}) do
        local previous = previous_manga_map[tostring(manga and manga.id)]
        local unchanged = previous
            and previous.chapters_last_fetched_at
            and manga and manga.chapters_last_fetched_at
            and previous.chapters_last_fetched_at == manga.chapters_last_fetched_at
        if not unchanged then
            if syncMangaChapters(credentials, manga) then
                synced = synced + 1
            else
                skipped = skipped + 1
            end
            if manga and manga.thumbnail_url and manga.thumbnail_url ~= "" then
                syncMangaCover(credentials, manga, previous)
            end
        end
        yieldToUI()
    end

    return self:writeResult(result_path, {
        ok = true,
        synced = synced,
        skipped = skipped,
    })
end

return FullSyncWorker
