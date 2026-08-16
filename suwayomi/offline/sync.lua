-- Boundary: offline library sync.
--
-- Responsibility: persist Suwayomi API results into the offline store so the
-- plugin can render library/chapter data when the server is unreachable.
-- Owned state: none.
-- Dependencies: SuwayomiOfflineStore.
-- External data: server API responses are validated before storage.

local SuwayomiOfflineStore = require("suwayomi/offline/store")

local SuwayomiOfflineSync = {}

function SuwayomiOfflineSync:syncCategories(categories)
    SuwayomiOfflineStore:setCategories(categories)
end

function SuwayomiOfflineSync:syncLibraryManga(library_result)
    if type(library_result) ~= "table" then
        return
    end
    local manga = library_result.manga
    if type(manga) ~= "table" then
        return
    end
    local manga_map = {}
    for _, entry in ipairs(manga) do
        if entry and entry.id then
            manga_map[tostring(entry.id)] = entry
        end
    end
    SuwayomiOfflineStore:setMangaMap(manga_map)
    SuwayomiOfflineStore:setLastSyncTime(os.time())
end

function SuwayomiOfflineSync:syncChapters(manga_id, chapters_result)
    if type(chapters_result) ~= "table" or not manga_id then
        return
    end
    local chapters = chapters_result.chapters
    if type(chapters) ~= "table" then
        return
    end
    local chapter_map = {}
    for _, chapter in ipairs(chapters) do
        if chapter and chapter.id then
            chapter_map[tostring(chapter.id)] = chapter
        end
    end
    SuwayomiOfflineStore:setChaptersMap(manga_id, chapter_map)
    self:syncReadProgress(manga_id, chapters)
end

function SuwayomiOfflineSync:syncReadProgress(manga_id, chapters)
    if type(chapters) ~= "table" then
        return
    end
    for _, chapter in ipairs(chapters) do
        if chapter and chapter.id and chapter.is_read == true then
            local existing = SuwayomiOfflineStore:getReadProgress(manga_id, chapter.id)
            if not existing or not existing.is_read then
                SuwayomiOfflineStore:setReadProgress(manga_id, chapter.id, {
                    is_read = true,
                    last_read_at = os.time(),
                })
            end
        end
    end
end

return SuwayomiOfflineSync
