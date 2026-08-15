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
    return true
end

local POSTER_CACHE_OPTIONS = {
    variant = "manga_poster",
    width = 240,
    height = 360,
}

local ROW_COVER_OPTIONS = {
    variant = "manga_cover",
    width = 64,
    height = 96,
}

local function syncMangaCover(credentials, manga, options)
    if not manga or not manga.thumbnail_url or manga.thumbnail_url == "" then
        return false
    end
    if ThumbnailCache.find(credentials, manga.thumbnail_url, options) then
        return true
    end
    local result_path = SubprocessJob.buildResultPath("thumbnail")
    local ok, result = pcall(function()
        return ThumbnailWorker:run(credentials, manga.thumbnail_url, result_path, options)
    end)
    pcall(function()
        os.remove(result_path)
    end)
    if not ok or not result or not result.ok then
        return false
    end
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
        end
        if manga and manga.thumbnail_url and manga.thumbnail_url ~= "" then
            syncMangaCover(credentials, manga, POSTER_CACHE_OPTIONS)
            syncMangaCover(credentials, manga, ROW_COVER_OPTIONS)
        end
    end

    return self:writeResult(result_path, {
        ok = true,
        synced = synced,
        skipped = skipped,
    })
end

return FullSyncWorker
