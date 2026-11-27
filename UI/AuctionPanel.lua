local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Market = ns.Market
local Catalog = ns.Catalog
local SidePanel = ns.SidePanel

local STRIP_HEIGHT, STRIP_TOP = 36, 8
local UNDERLINE_HEIGHT = 2
local SEGMENT_INSET, LINE_INSET, BONUS_GAP = 7, 5, 5
local SLIDE_TIME = 0.18
local SEGMENT_HOVER = { 1, 1, 1, 0.05 }
local CLEAR = { 1, 1, 1, 0 }

local Money, ShortMoney = SidePanel.Money, SidePanel.ShortMoney
local HOSTS = { "AuctionHouseFrame" }
local PRICE_UNKNOWN = "—"
local ESTIMATE_FORMAT = "≈ %s"
local FIND_ALL_MIN_ROWS = 2

local panel

local function ShownRank(entry)
    return entry.offer and entry.offer.rank
end

local function ShownItem(entry)
    return (ShownRank(entry) or entry.family.top).item
end

local function Detail(entry)
    local status = entry.status
    local offer = entry.offer
    if status == Market.SEARCHING then return L.AH_SEARCHING, C.muted end
    if status == Market.IDLE or status == Market.ENOUGH or status == Market.ESTIMATED then
        return SidePanel.Stock(entry), C.muted
    end
    if status == Market.NONE then return L.AH_NONE, C.bad end
    if status == Market.POOR then return L.AH_POOR, C.bad end
    if status == Market.BUYING then return L.AH_BUYING, C.accent end
    if status == Market.CONFIRM then return L.AH_PRICE_UP, C.warn end
    if status == Market.RAISED then
        return string.format(L.AH_RAISED, Money(Market.SeenPrice(offer.item)), Money(offer.base)), C.warn
    end
    if offer.quantity < entry.need and offer.beyond then
        return string.format(L.AH_CHEAP_ONLY, offer.quantity, Money(offer.beyond)), C.warn
    end
    if offer.quantity < entry.need then return string.format(L.AH_PARTIAL, offer.quantity), C.warn end
    return SidePanel.Stock(entry), C.muted
end

local function LotSize(entry)
    local offer = entry.offer
    if not offer or offer.status ~= Market.READY then return entry.need end
    if offer.kind == "item" and offer.auctions[1] then return offer.auctions[1].quantity end
    return offer.quantity
end

local function OfferFor(entry, rank)
    for _, offer in ipairs(entry.offers) do
        if offer.rank == rank then return offer end
    end
end

local function ButtonText(entry, confirm)
    if entry.status == Market.IDLE then return L.AH_FIND_PRICE end
    if confirm then return L.AH_CONFIRM end
    if entry.status == Market.ENOUGH then return L.AH_ENOUGH end
    return string.format(L.AH_BUY, LotSize(entry))
end

local function OnSale(offer)
    return offer ~= nil and offer.status == Market.READY
end

local AddLine = W.TooltipLine

local function LockLines(segment)
    local offer, rank = segment.offer, segment.rank
    if not offer then
        if rank.level > UnitLevel("player") then return AddLine(string.format(L.AH_LOCK_LEVEL, rank.level), C.bad) end
        return AddLine(L.AH_LOCK_LOWER, C.muted)
    end
    if Market.IsSettled(offer) then return AddLine(L.AH_NONE, C.bad) end
    AddLine(L.AH_SEARCHING, C.muted)
end

local function AddPriceLines(segment)
    local offer = segment.offer
    GameTooltip:AddLine(" ")
    if not OnSale(offer) then
        LockLines(segment)
        return
    end
    AddLine(string.format(L.AH_PER_ITEM, Money(offer.unitCost)), C.text)
    if offer.quantity > 0 then
        AddLine(string.format(L.AH_TIP_TOTAL, offer.quantity, Money(offer.cost)), C.muted)
    else
        AddLine(L.AH_TIP_ENOUGH, C.muted)
    end
    if offer.beyond then AddLine(string.format(L.AH_TIP_BEYOND, Money(offer.beyond)), C.warn) end
end

local function CanRefresh(entry)
    return entry.status ~= Market.BUYING
end

local function ShowSegmentTooltip(segment)
    local offer = segment.offer
    GameTooltip:SetOwner(segment, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(segment.rank.item)
    if not (offer and offer.status == Market.IDLE) then AddPriceLines(segment) end
    if offer and CanRefresh(offer.entry) then SidePanel.AddRightClick(L.AH_TIP_REFRESH) end
    GameTooltip:Show()
end

local function AddRowHints(entry)
    if not CanRefresh(entry) then return end
    SidePanel.AddRightClick(#entry.offers > 1 and L.AH_TIP_REFRESH_ALL or L.AH_TIP_REFRESH)
end

local function OnSegmentClick(entry, segment, button)
    if button == "RightButton" then
        if segment.offer then Market.Refresh(entry, segment.offer) end
    else
        Market.Pick(entry, segment.rank)
    end
end

local function CreateSegment(row, index)
    local segment = CreateFrame("Button", nil, row.strip)
    segment:SetHeight(STRIP_HEIGHT)
    segment:SetMotionScriptsWhileDisabled(true)
    local hover = segment:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    W.HoverFill(segment, hover, CLEAR, SEGMENT_HOVER)
    segment.rankText = UI.BoldText(segment, T.label, C.text)
    segment.rankText:SetPoint("TOPLEFT", SEGMENT_INSET, -LINE_INSET)
    segment.bonus = UI.Text(segment, T.label, C.muted)
    segment.bonus:SetPoint("LEFT", segment.rankText, "RIGHT", BONUS_GAP, 0)
    segment.price = UI.Text(segment, T.label, C.text)
    segment.price:SetPoint("BOTTOMLEFT", SEGMENT_INSET, LINE_INSET + UNDERLINE_HEIGHT)
    segment.price:SetPoint("RIGHT", -SEGMENT_INSET, 0)
    segment.price:SetJustifyH("LEFT")
    segment:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    segment:SetScript("OnClick", function(self, button) OnSegmentClick(row.entry, self, button) end)
    segment.UpdateTooltip = ShowSegmentTooltip
    segment:HookScript("OnEnter", ShowSegmentTooltip)
    segment:HookScript("OnLeave", W.HideHint)
    row.segments[index] = segment
    return segment
end

local function Divider(row, index)
    local divider = row.dividers[index]
    if divider then return divider end
    divider = row.strip:CreateTexture(nil, "BORDER")
    divider:SetColorTexture(unpack(C.window))
    divider:SetSize(1, STRIP_HEIGHT)
    row.dividers[index] = divider
    return divider
end

local function SegmentPrice(rank, offer)
    if not offer then
        if rank.level > UnitLevel("player") then return string.format(L.AH_LOCK_LEVEL_SHORT, rank.level), C.muted end
        return L.AH_LOCK_LOWER_SHORT, C.muted
    end
    if offer.status == Market.IDLE then
        if offer.estimate then return string.format(ESTIMATE_FORMAT, ShortMoney(offer.estimate)), C.muted end
        return PRICE_UNKNOWN, C.muted
    end
    if not Market.IsSettled(offer) then return "…", C.muted end
    if offer.status ~= Market.READY then return L.AH_NONE_SHORT, C.muted end
    return ShortMoney(offer.unitCost), Market.IsRaised(offer) and C.warn or C.text
end

local function PaintSegment(segment, rank, offer, chosen, buying)
    segment.rank, segment.offer = rank, offer
    segment.rankText:SetText(Catalog.RomanRank(rank))
    segment.rankText:SetTextColor(unpack(chosen and C.accent or C.text))
    segment.bonus:SetText(string.format(L.STAT_BONUS, rank.amount))
    local text, color = SegmentPrice(rank, offer)
    segment.price:SetText(text)
    segment.price:SetTextColor(unpack(color))
    local available = offer ~= nil and Market.IsAvailable(offer)
    segment:SetEnabled(offer ~= nil and not buying)
    segment:SetAlpha((available or chosen) and 1 or SidePanel.DISABLED_ALPHA)
    segment:Show()
end

local function MoveSelection(row, x, animate)
    local function Apply(_, value)
        row.selection:SetPoint("LEFT", value, 0)
        row.underline:SetPoint("BOTTOMLEFT", value, 0)
    end
    if animate then
        UI.Tween(row.slide, x, SLIDE_TIME, Apply)
    else
        UI.SnapTween(row.slide, x, Apply)
    end
end

local function PaintStrip(row, fresh)
    local entry = row.entry
    local ranks = entry.family.ranks
    local count = #ranks
    row.strip:SetShown(count > 1)
    if count < 2 then return end

    local width = (SidePanel.ROW_WIDTH - SidePanel.TEXT_INDENT) / count
    local buying = not CanRefresh(entry)
    local selected
    for index = 1, count do
        local rank = ranks[count - index + 1]
        local offer = OfferFor(entry, rank)
        local segment = row.segments[index] or CreateSegment(row, index)
        segment:SetWidth(width)
        segment:SetPoint("LEFT", (index - 1) * width, 0)
        local chosen = offer ~= nil and entry.offer == offer
        if chosen then selected = index end
        PaintSegment(segment, rank, offer, chosen, buying)
        if index > 1 then
            local divider = Divider(row, index)
            divider:SetPoint("LEFT", (index - 1) * width, 0)
            divider:Show()
        end
    end
    for index = count + 1, #row.segments do
        row.segments[index]:Hide()
        if row.dividers[index] then row.dividers[index]:Hide() end
    end

    local slide = row.selection:IsShown() and not fresh
    row.selection:SetShown(selected ~= nil)
    row.underline:SetShown(selected ~= nil)
    if not selected then return end
    row.selection:SetWidth(width)
    row.underline:SetWidth(width)
    MoveSelection(row, (selected - 1) * width, slide)
end

local function CreateStrip(row)
    local strip = CreateFrame("Frame", nil, row)
    strip:SetPoint("TOPLEFT", SidePanel.TEXT_INDENT, -(SidePanel.HEAD_HEIGHT + STRIP_TOP))
    strip:SetPoint("TOPRIGHT", 0, -(SidePanel.HEAD_HEIGHT + STRIP_TOP))
    strip:SetHeight(STRIP_HEIGHT)
    SidePanel.AddBackground(strip, C.control)
    row.selection = strip:CreateTexture(nil, "ARTWORK")
    row.selection:SetColorTexture(unpack(C.selected))
    row.selection:SetHeight(STRIP_HEIGHT)
    row.selection:Hide()
    row.underline = strip:CreateTexture(nil, "OVERLAY")
    row.underline:SetColorTexture(unpack(C.accent))
    row.underline:SetHeight(UNDERLINE_HEIGHT)
    row.underline:Hide()
    row.strip = strip
    row.segments = {}
    row.dividers = {}
    row.slide = {}
end

local function OnRowButton(entry)
    if entry.status == Market.IDLE then
        Market.FindPrices(entry)
    else
        Market.Buy(entry)
    end
end

local function RefreshRow(entry)
    Market.Refresh(entry)
end

local function CreateRow(owner)
    local row = SidePanel.NewRow(owner, OnRowButton, ShownItem, RefreshRow, AddRowHints)
    CreateStrip(row)
    return row
end

local function PaintRow(row, fresh)
    local entry = row.entry
    local rank = ShownRank(entry)
    row.icon:SetTexture(Catalog.Icon(entry.family, rank))
    row.name:SetText(rank and Catalog.RankName(entry.family, rank) or Catalog.Name(entry.family))
    local text, color = Detail(entry)
    row.detail:SetText(text)
    row.detail:SetTextColor(unpack(color))

    local status = entry.status
    local quoted = status == Market.CONFIRM
    local confirm = quoted or status == Market.RAISED
    local priced = status == Market.READY or status == Market.POOR or confirm
    local estimate = Market.EstimatedCost(entry)
    row.price:SetShown(priced or estimate ~= nil)
    if priced then
        row.price:SetText(Money(quoted and entry.quotedTotal or entry.offer.nextCost))
        row.price:SetTextColor(unpack(confirm and C.warn or C.text))
    elseif estimate then
        row.price:SetText(string.format(ESTIMATE_FORMAT, Money(estimate)))
        row.price:SetTextColor(unpack(C.muted))
    end

    row.button.text:SetText(ButtonText(entry, confirm))
    row.button:SetStyle(confirm and "primary" or "default")
    local buyable = status == Market.READY or status == Market.ESTIMATED or confirm
    SidePanel.SetEnabled(row.button, status == Market.IDLE or buyable)
    PaintStrip(row, fresh)
    local strip = #entry.family.ranks > 1 and STRIP_TOP + STRIP_HEIGHT or 0
    row:SetHeight(SidePanel.HEAD_HEIGHT + strip)
end

local function Paint()
    panel.subtitle:SetText(ns.db.lowerRanks and L.AH_SUBTITLE_LOWER or L.AH_SUBTITLE)
    local waiting, known = Market.PriceCounts()
    local total, approximate, counted = Market.Total()
    local offerAll = waiting >= FIND_ALL_MIN_ROWS
    local showTotal = counted > 0
    panel:SetFooterShown(offerAll or showTotal)
    panel:PaintRows(Market.entries, CreateRow, PaintRow)
    panel.footerText:SetText(string.format(approximate and L.AH_ABOUT or L.AH_TOTAL, Money(total)))
    panel.footerText:SetShown(showTotal)
    panel:SetAction(L.AH_FIND_PRICES, true)
    panel.action:SetShown(offerAll)
    panel.refresh:SetShown(known > 0)
end

local function Create()
    panel = SidePanel.Create("ReScrollAuctionPanel", {
        title = "AH_TITLE",
        empty = "AH_EMPTY",
        refresh = function() Market.Refresh() end,
        onAction = function() Market.FindPrices() end,
        toggles = { { key = "countBank", label = "COUNT_BANK", desc = "COUNT_BANK_DESC" } },
        hosts = HOSTS,
        slot = "auction",
        offset = { x = "auctionX", y = "auctionY" },
        settingsPage = "auction",
    })
end

ns.Listen("MARKET_SHOWN", function(open)
    if not open then
        if panel then panel:Hide() end
        return
    end
    if not panel then Create() end
    Paint()
    panel:Open()
end)

local function RepaintIfShown()
    if panel and panel:IsShown() then Paint() end
end

ns.Listen("MARKET_CHANGED", RepaintIfShown)
ns.Listen("LOCALE_CHANGED", RepaintIfShown)
ns.Listen("NAMES_CHANGED", RepaintIfShown)
