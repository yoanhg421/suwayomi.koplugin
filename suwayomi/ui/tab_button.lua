-- Boundary: a bottom tab button with an icon above a label.
--
-- Responsibility: render a tappable icon+text cell for the bottom tab bar.
-- Owned state: the icon and text widgets, the tap area.
-- Dependencies: ImageWidget, TextWidget, VerticalGroup, CenterContainer,
--               InputContainer, Font, Blitbuffer, Screen.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = require("device").screen
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")

local SuwayomiTabButton = InputContainer:extend{
    name = "suwayomi_tab_button",
}

function SuwayomiTabButton:init()
    self.dimen = Geom:new{
        w = self.width or 0,
        h = self.height or 0,
    }
    self.icon_size = self.icon_size or Screen:scaleBySize(32)

    local vgroup = VerticalGroup:new{ align = "center" }
    if self.icon_path and self.icon_path ~= "" then
        local icon_ok, icon_widget = pcall(function()
            return ImageWidget:new{
                file = self.icon_path,
                width = self.icon_size,
                height = self.icon_size,
            }
        end)
        if icon_ok then
            table.insert(vgroup, icon_widget)
        end
    end

    table.insert(vgroup, TextWidget:new{
        text = self.text or "",
        face = self.face or Font:getFace("xx_smallinfofont"),
        fgcolor = self.text_color or Blitbuffer.COLOR_BLACK,
    })

    self[1] = CenterContainer:new{
        dimen = self.dimen,
        vgroup,
    }

    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
    }
end

function SuwayomiTabButton:onTapSelect()
    if type(self.callback) == "function" then
        self.callback()
    end
    return true
end

return SuwayomiTabButton
