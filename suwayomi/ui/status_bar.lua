-- Boundary: Suwayomi top status bar widget.
--
-- Responsibility: display time, battery and Wi-Fi in a top bar that can be
-- used as a custom Menu title bar, keeping the KOReader top menu reachable
-- on a tap outside the optional left icon.
-- Owned state: left and right TextWidget labels, optional left icon.
-- Dependencies: KOReader widget containers, TextWidget, IconButton, UIManager.
-- External data: rendered as the custom title bar of the library ListMenu.

local Device = require("device")
local Font   = require("ui/font")
local Geom   = require("ui/geometry")
local Size   = require("ui/size")

local Screen = Device.screen

local UIManager      = require("ui/uimanager")
local OverlapGroup   = require("ui/widget/overlapgroup")
local LeftContainer  = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local IconButton      = require("ui/widget/iconbutton")
local TextWidget      = require("ui/widget/textwidget")

local SuwayomiStatusBar = OverlapGroup:extend{
    name = "suwayomi_status_bar",
}

function SuwayomiStatusBar:init()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width or Screen:getWidth(),
        h = Screen:scaleBySize(36),
    }
    self.titlebar_height = self.dimen.h
    self.face = self.face or Font:getFace("x_smallinfofont")

    self.left_text_widget = TextWidget:new{
        text = self.left_text or " ",
        face = self.face,
        padding = 0,
    }
    self.right_text_widget = TextWidget:new{
        text = self.right_text or " ",
        face = self.face,
        padding = 0,
    }

    self:refreshLeftGroup()
    self[2] = RightContainer:new{
        dimen = self.dimen:copy(),
        self.right_text_widget,
    }
end

function SuwayomiStatusBar:refreshLeftGroup()
    local left_group = HorizontalGroup:new{ align = "center" }
    if self.left_icon then
        local icon_size = Screen:scaleBySize(24)
        local icon = IconButton:new{
            icon = self.left_icon,
            width = icon_size,
            height = icon_size,
            padding = 0,
            allow_flash = false,
            show_parent = self,
        }
        icon.callback = function()
            if self.show_parent and self.show_parent.onLeftButtonTap then
                self.show_parent:onLeftButtonTap()
            end
        end
        table.insert(left_group, icon)
        table.insert(left_group, HorizontalSpan:new{ width = Size.padding.small })
    end
    table.insert(left_group, self.left_text_widget)
    self[1] = LeftContainer:new{
        dimen = self.dimen:copy(),
        left_group,
    }
end

function SuwayomiStatusBar:getHeight()
    return self.titlebar_height
end

function SuwayomiStatusBar:setTitle(text)
    if self.left_text_widget and self.left_text_widget.setText then
        self.left_text_widget:setText(text or " ")
        UIManager:setDirty(self.show_parent or self, "ui", self.dimen)
    end
end

function SuwayomiStatusBar:setSubTitle(text)
    if self.right_text_widget and self.right_text_widget.setText then
        self.right_text_widget:setText(text or " ")
        UIManager:setDirty(self.show_parent or self, "ui", self.dimen)
    end
end

function SuwayomiStatusBar:setLeftIcon(icon)
    self.left_icon = icon
    self:refreshLeftGroup()
    UIManager:setDirty(self.show_parent or self, "ui", self.dimen)
end

return SuwayomiStatusBar
