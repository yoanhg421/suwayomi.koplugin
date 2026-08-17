-- Boundary: offline local library store.
--
-- Responsibility: persist manga, chapter, category, and read-progress metadata
-- on the device so the plugin can work when Suwayomi is unreachable.
-- Owned state: cached LuaSettings handle and offline file path.
-- Dependencies: datastorage and luasettings.
-- External data: manga/chapter metadata, filesystem paths, and read progress
-- are stored in the KOReader settings directory.

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local SuwayomiOfflineStore = {
    offline_file = DataStorage:getSettingsDir() .. "/suwayomi_offline.lua",
    store = nil,
}

function SuwayomiOfflineStore:reset()
    self.store = nil
end

function SuwayomiOfflineStore:setOfflineFile(path)
    self.offline_file = path
    self.store = nil
end

function SuwayomiOfflineStore:open()
    if not self.store then
        self.store = LuaSettings:open(self.offline_file)
    end
    return self.store
end

function SuwayomiOfflineStore:getCategories()
    return self:open():readSetting("categories", {})
end

function SuwayomiOfflineStore:setCategories(categories)
    self:open():saveSetting("categories", categories or {}):flush()
end

function SuwayomiOfflineStore:getMangaMap()
    return self:open():readSetting("manga", {})
end

function SuwayomiOfflineStore:getMangaList()
    local manga = self:open():readSetting("manga", {})
    local list = {}
    for _, manga_data in pairs(manga) do
        table.insert(list, manga_data)
    end
    table.sort(list, function(left, right)
        local left_title = tostring(left and left.title or ""):lower()
        local right_title = tostring(right and right.title or ""):lower()
        return left_title < right_title
    end)
    return list
end

function SuwayomiOfflineStore:setMangaMap(manga_map)
    self:open():saveSetting("manga", manga_map or {}):flush()
end

function SuwayomiOfflineStore:getChaptersMap(manga_id)
    local chapters = self:open():readSetting("chapters", {})
    return chapters[tostring(manga_id)] or {}
end

function SuwayomiOfflineStore:setChaptersMap(manga_id, chapter_map)
    local chapters = self:open():readSetting("chapters", {})
    chapters[tostring(manga_id)] = chapter_map or {}
    self:open():saveSetting("chapters", chapters):flush()
end

function SuwayomiOfflineStore:getChaptersList(manga_id)
    local chapters_map = self:getChaptersMap(manga_id)
    local list = {}
    for _, chapter in pairs(chapters_map) do
        table.insert(list, chapter)
    end
    table.sort(list, function(left, right)
        local left_number = tonumber(left and left.chapter_number)
        local right_number = tonumber(right and right.chapter_number)
        if left_number and right_number then
            return left_number < right_number
        end
        if left_number then
            return true
        end
        if right_number then
            return false
        end
        local left_order = tonumber(left and left.source_order) or 0
        local right_order = tonumber(right and right.source_order) or 0
        return left_order < right_order
    end)
    return list
end

function SuwayomiOfflineStore:getReadProgress(manga_id, chapter_id)
    local progress = self:open():readSetting("read_progress", {})
    local manga_progress = progress[tostring(manga_id)]
    if not manga_progress then
        return nil
    end
    return manga_progress[tostring(chapter_id)]
end

function SuwayomiOfflineStore:setReadProgress(manga_id, chapter_id, progress)
    local all_progress = self:open():readSetting("read_progress", {})
    local manga_key = tostring(manga_id)
    local chapter_key = tostring(chapter_id)
    all_progress[manga_key] = all_progress[manga_key] or {}
    all_progress[manga_key][chapter_key] = {
        page = tonumber(progress and progress.page) or 0,
        is_read = progress and progress.is_read == true,
        last_read_at = (progress and tonumber(progress.last_read_at)) or os.time(),
    }
    self:open():saveSetting("read_progress", all_progress):flush()
end

function SuwayomiOfflineStore:getMangaListByLastRead()
    local manga_list = self:getMangaList()
    local all_progress = self:open():readSetting("read_progress", {})
    local result = {}
    for _, manga in ipairs(manga_list) do
        local manga_id = tostring(manga and manga.id)
        local manga_progress = all_progress[manga_id] or {}
        local last_read_at = 0
        for _, chapter_progress in pairs(manga_progress) do
            if type(chapter_progress) == "table" and chapter_progress.is_read == true then
                last_read_at = math.max(last_read_at, tonumber(chapter_progress.last_read_at) or 0)
            end
        end
        if last_read_at > 0 then
            manga._suwayomi_last_read_at = last_read_at
            table.insert(result, manga)
        end
    end
    table.sort(result, function(a, b)
        local a_at = a._suwayomi_last_read_at or 0
        local b_at = b._suwayomi_last_read_at or 0
        if a_at == b_at then
            return tostring(a.title or "") < tostring(b.title or "")
        end
        return a_at > b_at
    end)
    return result
end

function SuwayomiOfflineStore:setRecentMangaList(manga_list)
    self:open():saveSetting("recent_manga_list", manga_list or {}):flush()
end

function SuwayomiOfflineStore:getRecentMangaList()
    return self:open():readSetting("recent_manga_list", {})
end

function SuwayomiOfflineStore:setChapterHistory(history)
    self:open():saveSetting("chapter_history", history or {}):flush()
end

function SuwayomiOfflineStore:getChapterHistory()
    return self:open():readSetting("chapter_history", {})
end

function SuwayomiOfflineStore:getLastSyncTime()
    return tonumber(self:open():readSetting("last_sync_at", 0)) or 0
end

function SuwayomiOfflineStore:setLastSyncTime(timestamp)
    self:open():saveSetting("last_sync_at", tonumber(timestamp) or os.time()):flush()
end

return SuwayomiOfflineStore
