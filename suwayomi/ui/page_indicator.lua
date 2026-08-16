-- Boundary: tab page indicator dots.
--
-- Responsibility: render a row of centered filled dots that show the current
-- page number inside a paged grid.
-- Owned state: dot widgets.
-- Dependencies: HorizontalGroup, TextWidget, UIManager, Font, Blitbuffer.

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local SuwayomiPageIndicator = HorizontalGroup:extend{
    name = "suwayomi_page_indicator",
}

local DOT = "\u{25CF}"

function SuwayomiPageIndicator:init()
    self.face = self.face or Font:getFace("xx_smallinfofont", 10)
    self:clear()
    self:setActive(self.page or 1, self.total or 1)
end

function SuwayomiPageIndicator:clear()
    for _, dot in ipairs(self.dots or {}) do
        if dot.free then
            dot:free()
        end
    end
    self.dots = {}
    for i = #self, 1, -1 do
        table.remove(self, i)
    end
end

function SuwayomiPageIndicator:setActive(page, total)
    page = page or 1
    total = total or 1
    self:clear()
    for i = 1, total do
        table.insert(self, TextWidget:new{
            text = DOT,
            face = self.face,
            fgcolor = (i == page) and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY,
        })
        if i < total then
            table.insert(self, HorizontalSpan:new{ width = 6 })
        end
    end
    self:resetLayout()
    UIManager:setDirty(self.show_parent or self, "ui")
end

return SuwayomiPageIndicator
