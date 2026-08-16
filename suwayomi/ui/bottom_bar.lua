-- Boundary: Bottom tab bar for the Suwayomi home screen.
--
-- Responsibility: render a row of tappable icon+text tab buttons at the
-- bottom of the home screen and dispatch the configured actions.
-- Owned state: the tab button widgets.
-- Dependencies: SuwayomiTabButton, HorizontalGroup, Screen, Size.

local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Screen = require("device").screen
local SuwayomiTabButton = require("suwayomi/ui/tab_button")

local SuwayomiBottomBar = HorizontalGroup:extend{
    name = "suwayomi_bottom_bar",
    allow_mirroring = false,
    height = nil,
    icon_dir = nil,
    icon_size = nil,
}

function SuwayomiBottomBar:init()
    local buttons = self.buttons or {}
    local count = #buttons
    local bar_height = self.height or Screen:scaleBySize(70)
    local screen_w = Screen:getWidth()
    local button_w = count > 0 and math.floor(screen_w / count) or screen_w
    local icon_dir = self.icon_dir and (self.icon_dir:gsub("([^/])$", "%1/")) or ""

    for _, spec in ipairs(buttons) do
        local icon_path
        if spec.icon and spec.icon ~= "" then
            if spec.icon:match("^/") then
                icon_path = spec.icon
            else
                icon_path = icon_dir .. spec.icon
            end
        end
        table.insert(self, SuwayomiTabButton:new{
            text = spec.text,
            icon_path = icon_path,
            width = button_w,
            height = bar_height,
            callback = spec.action,
            icon_size = self.icon_size,
        })
    end
    self:resetLayout()
    self.dimen = Geom:new{ w = screen_w, h = bar_height }
end

return SuwayomiBottomBar
