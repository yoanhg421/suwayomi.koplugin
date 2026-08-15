package.path = "?.lua;" .. package.path

describe("suwayomi/offline/store", function()
    local flushed
    local stored_data
    local opened_path

    before_each(function()
        flushed = false
        stored_data = {}
        opened_path = nil

        package.loaded["suwayomi/offline/store"] = nil
        package.loaded.datastorage = nil
        package.loaded.luasettings = nil

        package.preload.datastorage = function()
            return {
                getSettingsDir = function()
                    return "/mock/settings"
                end,
            }
        end

        package.preload.luasettings = function()
            return {
                open = function(_, path)
                    opened_path = path
                    return {
                        file = path,
                        data = stored_data,
                        readSetting = function(self, key, default)
                            if self.data[key] == nil and default ~= nil then
                                self.data[key] = default
                            end
                            return self.data[key]
                        end,
                        saveSetting = function(self, key, value)
                            self.data[key] = value
                            return self
                        end,
                        flush = function()
                            flushed = true
                        end,
                    }
                end,
            }
        end
    end)

    after_each(function()
        package.preload.datastorage = nil
        package.preload.luasettings = nil
    end)

    it("uses the KOReader settings directory for the offline store file", function()
        local store = require("suwayomi/offline/store")
        store:open()
        assert.are.equal("/mock/settings/suwayomi_offline.lua", opened_path)
    end)

    it("loads and saves categories", function()
        local store = require("suwayomi/offline/store")
        assert.are.same({}, store:getCategories())

        store:setCategories({ { id = "1", name = "Default" } })
        assert.is_true(flushed)
        assert.are.same({ { id = "1", name = "Default" } }, store:getCategories())
    end)

    it("loads and saves the manga map as a sorted list", function()
        local store = require("suwayomi/offline/store")
        assert.are.same({}, store:getMangaList())

        store:setMangaMap({
            m2 = { id = "m2", title = "Berserk" },
            m1 = { id = "m1", title = "Akira" },
        })
        assert.is_true(flushed)
        local list = store:getMangaList()
        assert.are.equal("Akira", list[1].title)
        assert.are.equal("Berserk", list[2].title)
    end)

    it("loads and saves chapters for a manga", function()
        local store = require("suwayomi/offline/store")
        assert.are.same({}, store:getChaptersMap("m1"))

        store:setChaptersMap("m1", {
            c1 = { id = "c1", name = "Ch. 1" },
            c2 = { id = "c2", name = "Ch. 2" },
        })
        assert.is_true(flushed)
        local chapters = store:getChaptersMap("m1")
        assert.are.equal("Ch. 1", chapters.c1.name)
    end)

    it("returns a sorted list of chapters for a manga", function()
        local store = require("suwayomi/offline/store")
        store:setChaptersMap("m1", {
            c2 = { id = "c2", name = "Ch. 2", chapter_number = "2" },
            c1 = { id = "c1", name = "Ch. 1", chapter_number = "1" },
        })
        local list = store:getChaptersList("m1")
        assert.are.equal("c1", list[1].id)
        assert.are.equal("c2", list[2].id)
    end)

    it("tracks read progress per manga and chapter", function()
        local store = require("suwayomi/offline/store")
        assert.is_nil(store:getReadProgress("m1", "c1"))

        store:setReadProgress("m1", "c1", { page = 5, is_read = false, last_read_at = 1000 })
        assert.is_true(flushed)

        local progress = store:getReadProgress("m1", "c1")
        assert.are.equal(5, progress.page)
        assert.is_false(progress.is_read)
        assert.are.equal(1000, progress.last_read_at)
    end)

    it("tracks the last successful sync time", function()
        local store = require("suwayomi/offline/store")
        assert.are.equal(0, store:getLastSyncTime())

        store:setLastSyncTime(1234567)
        assert.is_true(flushed)
        assert.are.equal(1234567, store:getLastSyncTime())
    end)
end)
