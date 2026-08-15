-- Boundary: Bottom tab bar for the Suwayomi home screen.
--
-- Responsibility: render a row of tappable tab buttons at the bottom of the
-- home screen and dispatch the configured actions.
-- Owned state: the button widgets and their callbacks.
-- Dependencies: KOReader Button, HorizontalGroup, Screen.

local Button = require("ui/widget/button")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Screen = require("device").screen
local Size = require("ui/size")

local SuwayomiBottomBar = HorizontalGroup:extend{
    name = "suwayomi_bottom_bar",
    allow_mirroring = false,
    height = nil,
}

function SuwayomiBottomBar:init()
    local buttons = self.buttons or {}
    local count = #buttons
    local bar_height = self.height or Size.item.height_default
    local screen_w = Screen:getWidth()
    local button_w = count > 0 and math.floor(screen_w / count) or screen_w
    local button_h = bar_height

    for _, spec in ipairs(buttons) do
        local action = spec.action
        local button = Button:new{
            text = spec.text,
            show_parent = self.show_parent or self,
            width = button_w,
            height = button_h,
            bordersize = 0,
            radius = 0,
            padding = Size.padding.small,
            text_font_face = "smallinfofont",
            text_font_size = 16,
            text_font_bold = false,
            avoid_text_truncation = false,
            callback = function()
                if type(action) == "function" then
                    action()
                end
            end,
        }
        table.insert(self, button)
    end
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = screen_w, h = button_h,
    }
end

function SuwayomiBottomBar:getSize()
    return self.dimen
end

return SuwayomiBottomBar
