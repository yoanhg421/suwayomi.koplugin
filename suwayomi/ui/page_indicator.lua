-- Boundary: tab page indicator dots.
--
-- Responsibility: render a row of filled/unfilled dots that show the current
-- page number inside a paged grid.
-- Owned state: dot widgets.
-- Dependencies: HorizontalGroup, TextWidget, UIManager, Font and Size.

local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local SuwayomiPageIndicator = HorizontalGroup:extend{
    name = "suwayomi_page_indicator",
}

local ACTIVE_DOT = "\u{25CF}"
local INACTIVE_DOT = "\u{25CB}"

function SuwayomiPageIndicator:init()
    self.face = self.face or Font:getFace("xx_smallinfofont")
    self.dots = {}
    self:clear(true)
    self:setActive(self.page or 1, self.total or 1)
    HorizontalGroup.init(self)
end

function SuwayomiPageIndicator:clear(skip_init)
    for _, dot in ipairs(self.dots or {}) do
        if dot.free then
            dot:free()
        end
    end
    self.dots = {}
    if not skip_init then
        self:resetLayout()
    end
end

function SuwayomiPageIndicator:setActive(page, total)
    page = page or 1
    total = total or 1
    self:clear()
    for i = 1, total do
        table.insert(self.dots, TextWidget:new{
            text = (i == page) and ACTIVE_DOT or INACTIVE_DOT,
            face = self.face,
        })
    end
    self[1] = nil
    for _, dot in ipairs(self.dots) do
        table.insert(self, dot)
        table.insert(self, HorizontalSpan:new{ width = 8 })
    end
    table.remove(self)
    self:resetLayout()
    UIManager:setDirty(self.show_parent or self, "ui", self.dimen)
end

return SuwayomiPageIndicator
