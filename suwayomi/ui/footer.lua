-- Boundary: home screen footer container.
--
-- Responsibility: stack the page-indicator dots above the bottom tab bar.
-- Owned state: the page indicator and bottom bar widgets.
-- Dependencies: VerticalGroup, SuwayomiPageIndicator.

local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local SuwayomiPageIndicator = require("suwayomi/ui/page_indicator")

local SuwayomiFooter = VerticalGroup:extend{
    name = "suwayomi_footer",
}

function SuwayomiFooter:init()
    self.page_indicator = SuwayomiPageIndicator:new{
        page = 1,
        total = 1,
    }
    self.bottom_bar = self.bottom_bar
    self[1] = self.page_indicator
    self[2] = VerticalSpan:new{ width = 4 }
    self[3] = self.bottom_bar
    self:resetLayout()
end

function SuwayomiFooter:updatePage(page, total)
    if self.page_indicator then
        self.page_indicator:setActive(page, total)
    end
end

return SuwayomiFooter
