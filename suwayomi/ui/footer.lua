-- Boundary: home screen footer container.
--
-- Responsibility: center the page-indicator dots above a top border line
-- and the bottom tab bar.
-- Owned state: the page indicator, top border, and bottom bar widgets.
-- Dependencies: VerticalGroup, CenterContainer, LineWidget, Geom, Blitbuffer,
--               Screen, SuwayomiPageIndicator.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local LineWidget = require("ui/widget/linewidget")
local Screen = require("device").screen
local Size = require("ui/size")
local SuwayomiPageIndicator = require("suwayomi/ui/page_indicator")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local SuwayomiFooter = VerticalGroup:extend{
    name = "suwayomi_footer",
    align = "center",
}

function SuwayomiFooter:init()
    self.dimen = nil
    self._size = nil
    local screen_w = Screen:getWidth()
    self.page_indicator = SuwayomiPageIndicator:new{
        page = 1,
        total = 1,
    }
    local top_line = LineWidget:new{
        dimen = Geom:new{
            w = screen_w,
            h = Size.line.thin,
        },
        color = Blitbuffer.COLOR_DARK_GRAY,
        style = "solid",
    }
    self.bottom_bar = self.bottom_bar
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = screen_w,
            h = self.page_indicator:getSize().h,
        },
        self.page_indicator,
    }
    self[2] = top_line
    self[3] = VerticalSpan:new{ width = 2 }
    self[4] = self.bottom_bar
    self:resetLayout()
end

function SuwayomiFooter:updatePage(page, total)
    if self.page_indicator then
        self.page_indicator:setActive(page, total)
    end
end

return SuwayomiFooter
