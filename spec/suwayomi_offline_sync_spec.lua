package.path = "?.lua;" .. package.path

describe("suwayomi/offline/sync", function()
    local store_spy
    local last_sync

    before_each(function()
        store_spy = {
            setCategories = {},
            setMangaMap = {},
            setChaptersMap = {},
            setLastSyncTime = nil,
        }
        last_sync = nil

        package.loaded["suwayomi/offline/store"] = nil
        package.loaded["suwayomi/offline/sync"] = nil

        package.preload["suwayomi/offline/store"] = function()
            return {
                setCategories = function(_, value)
                    table.insert(store_spy.setCategories, value)
                end,
                setMangaMap = function(_, value)
                    table.insert(store_spy.setMangaMap, value)
                end,
                setChaptersMap = function(_, manga_id, value)
                    store_spy.setChaptersMap[manga_id] = value
                end,
                setLastSyncTime = function(_, timestamp)
                    last_sync = timestamp
                end,
            }
        end
    end)

    after_each(function()
        package.preload["suwayomi/offline/store"] = nil
    end)

    it("stores categories unchanged", function()
        local sync = require("suwayomi/offline/sync")
        sync:syncCategories({ { id = "1", name = "Default" } })
        assert.are.same({ { { id = "1", name = "Default" } } }, store_spy.setCategories)
    end)

    it("stores library manga as a map by id", function()
        local sync = require("suwayomi/offline/sync")
        sync:syncLibraryManga({
            manga = {
                { id = "m1", title = "Akira" },
                { id = "m2", title = "Berserk" },
            },
            total_count = 2,
        })
        assert.are.equal("Akira", store_spy.setMangaMap[1].m1.title)
        assert.are.equal("Berserk", store_spy.setMangaMap[1].m2.title)
        assert.is_number(last_sync)
    end)

    it("stores chapters for a manga as a map by id", function()
        local sync = require("suwayomi/offline/sync")
        sync:syncChapters("m1", {
            chapters = {
                { id = "c1", name = "Ch. 1" },
                { id = "c2", name = "Ch. 2" },
            },
        })
        assert.are.equal("Ch. 1", store_spy.setChaptersMap.m1.c1.name)
    end)

    it("ignores bad inputs", function()
        local sync = require("suwayomi/offline/sync")
        sync:syncLibraryManga(nil)
        sync:syncChapters("m1", nil)
        sync:syncChapters(nil, { chapters = {} })
        assert.are.same({}, store_spy.setMangaMap)
        assert.are.same({}, store_spy.setChaptersMap)
    end)
end)
