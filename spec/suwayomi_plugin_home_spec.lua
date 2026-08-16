package.path = "?.lua;" .. package.path

local helper = require("spec/support/controller_module_spec_helper")

describe("suwayomi/plugin/home", function()
    after_each(function()
        package.preload["suwayomi/i18n"] = nil
        package.loaded["suwayomi/i18n"] = nil
    end)

    it("exports the home/menu methods as a controller boundary", function()
        helper.assertControllerModule("suwayomi/plugin/home", {
            "showHome",
            "showMessage",
            "withLoadingMessage",
            "addToMainMenu",
        })
    end)

    it("only exposes Open, Sync, and Settings in the Suwayomi tab", function()
        package.loaded["suwayomi/plugin/home"] = nil
        helper.stubControllerDependencies()
        local HomeController = require("suwayomi/plugin/home")
        local plugin = {
            isBookMode = function()
                return false
            end,
        }
        for name, method in pairs(HomeController.methods) do
            plugin[name] = method
        end

        local menu_items = {}
        plugin:addToMainMenu(menu_items)

        assert.is_truthy(menu_items.suwayomi_open)
        assert.is_truthy(menu_items.suwayomi_sync)
        assert.is_truthy(menu_items.suwayomi_settings)
        assert.is_nil(menu_items.suwayomi_library)
        assert.is_nil(menu_items.suwayomi_browse)
        assert.is_nil(menu_items.suwayomi_downloads)
    end)

    it("routes home action labels through i18n", function()
        package.preload.gettext = function()
            return function(text)
                return text
            end
        end
        package.preload["suwayomi/i18n"] = function()
            return {
                t = function(text)
                    return "tx:" .. text
                end,
            }
        end
        package.loaded["suwayomi/plugin/home"] = nil
        package.loaded["suwayomi/i18n"] = nil

        local controller = require("suwayomi/plugin/home")
        local plugin = {}
        for name, method in pairs(controller.methods) do
            plugin[name] = method
        end

        local actions = plugin:buildHomeActions()

        assert.are.equal("tx:Library", actions[1].text)
        assert.are.equal("tx:Close plugin", actions[#actions].text)
    end)

    it("cleans marker i18n stubs between tests", function()
        assert.is_nil(package.preload["suwayomi/i18n"])
        assert.is_nil(package.loaded["suwayomi/i18n"])
    end)
end)
