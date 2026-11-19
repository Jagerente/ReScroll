local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Market = ns.Market
local Catalog = ns.Catalog
local SidePanel = ns.SidePanel

local AuctionPanel = {}
ns.AuctionPanel = AuctionPanel

local STRIP_HEIGHT, STRIP_TOP = 36, 8
local UNDERLINE_HEIGHT = 2
local SEGMENT_INSET, LINE_INSET, BONUS_GAP = 7, 5, 5
local SLIDE_TIME = 0.18
local SELECTED_FILL = { 0.243, 0.235, 0.220, 1 }
local SEGMENT_HOVER = { 1, 1, 1, 0.05 }
local CLEAR = { 1, 1, 1, 0 }

local Money, ShortMoney = SidePanel.Money, SidePanel.ShortMoney
local HOSTS = { "AuctionHouseFrame" }

local panel

local function ShownRank(entry)
    return entry.offer and entry.offer.rank
end

local function ShownItem(entry)
    return (ShownRank(entry) or entry.family.top).item
end

local function Stock(entry)
    local target = ns.Inventory.StockTarget(entry.family)
    if entry.mail > 0 then
        if entry.bank > 0 then return string.format(L.AH_HAVE_BANK_MAIL, entry.have, target, entry.bank, entry.mail) end
        return string.format(L.AH_HAVE_MAIL, entry.have, target, entry.mail)
    end
    if entry.bank > 0 then return string.format(L.AH_HAVE_BANK, entry.have, target, entry.bank) end
    return string.format(L.AH_HAVE, entry.have, target)
end

local function Detail(entry)
    local status = entry.status
    local offer = entry.offer
    if status == Market.SEARCHING then return L.AH_SEARCHING, C.muted end
    if status == Market.ENOUGH then return Stock(entry), C.muted end
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
    return Stock(entry), C.muted
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
    if confirm then return L.AH_CONFIRM end
    if entry.status == Market.ENOUGH then return L.AH_ENOUGH end
    return string.format(L.AH_BUY, LotSize(entry))
end

local function OnSale(offer)
    return offer ~= nil and offer.status == Market.READY
end

local function AddLine(text, color)
    GameTooltip:AddLine(text, color[1], color[2], color[3], true)
end

local function LockLines(segment)
    local offer, rank = segment.offer, segment.rank
    if not offer then
        if rank.level > UnitLevel("player") then return AddLine(string.format(L.AH_LOCK_LEVEL, rank.level), C.bad) end
        return AddLine(L.AH_LOCK_LOWER, C.muted)
    end
    if Market.IsSettled(offer) then return AddLine(L.AH_NONE, C.bad) end
    AddLine(L.AH_SEARCHING, C.muted)
end

local function ShowSegmentTooltip(segment)
    local offer = segment.offer
    GameTooltip:SetOwner(segment, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(segment.rank.item)
    GameTooltip:AddLine(" ")
    if not OnSale(offer) then
        LockLines(segment)
    else
        AddLine(string.format(L.AH_PER_SCROLL, Money(offer.unitCost)), C.text)
        if offer.quantity > 0 then
            AddLine(string.format(L.AH_TIP_AVAILABLE, offer.quantity), C.muted)
            AddLine(string.format(L.AH_TIP_TOTAL, offer.quantity, Money(offer.cost)), C.muted)
        else
            AddLine(L.AH_TIP_ENOUGH, C.muted)
        end
        if offer.beyond then AddLine(string.format(L.AH_TIP_BEYOND, Money(offer.beyond)), C.warn) end
        if offer.entry.offer ~= offer then AddLine(L.AH_TIP_PICK, C.accent) end
    end
    GameTooltip:Show()
end

local function CreateSegment(row, index)
    local segment = CreateFrame("Button", nil, row.strip)
    segment:SetHeight(STRIP_HEIGHT)
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
    segment:SetScript("OnClick", function(self) Market.Pick(row.entry, self.rank) end)
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
    if not Market.IsSettled(offer) then return "…", C.muted end
    if offer.status ~= Market.READY then return L.AH_NONE_SHORT, C.muted end
    return ShortMoney(offer.unitCost), Market.IsRaised(offer) and C.warn or C.text
end

local function PaintSegment(segment, rank, offer, chosen, busy)
    segment.rank, segment.offer = rank, offer
    segment.rankText:SetText(ns.Bar.RomanRank(rank))
    segment.rankText:SetTextColor(unpack(chosen and C.accent or C.text))
    segment.bonus:SetText(string.format(L.STAT_BONUS, rank.amount))
    local text, color = SegmentPrice(rank, offer)
    segment.price:SetText(text)
    segment.price:SetTextColor(unpack(color))
    local pending = offer ~= nil and not Market.IsSettled(offer)
    segment:SetEnabled(OnSale(offer) and not busy)
    segment:SetAlpha((OnSale(offer) or pending or chosen) and 1 or SidePanel.DISABLED_ALPHA)
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
    local busy = entry.status == Market.BUYING or entry.status == Market.CONFIRM
    local selected
    for index = 1, count do
        local rank = ranks[count - index + 1]
        local offer = OfferFor(entry, rank)
        local segment = row.segments[index] or CreateSegment(row, index)
        segment:SetWidth(width)
        segment:SetPoint("LEFT", (index - 1) * width, 0)
        local chosen = offer ~= nil and entry.offer == offer
        if chosen then selected = index end
        PaintSegment(segment, rank, offer, chosen, busy)
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
    row.selection:SetColorTexture(unpack(SELECTED_FILL))
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

local function CreateRow(owner)
    local row = SidePanel.NewRow(owner, Market.Buy, ShownItem)
    CreateStrip(row)
    return row
end

local function PaintRow(row, fresh)
    local entry = row.entry
    local rank = ShownRank(entry)
    row.icon:SetTexture(Catalog.Icon(entry.family, rank))
    row.name:SetText(rank and SidePanel.ScrollName(entry.family, rank) or Catalog.Name(entry.family))
    local text, color = Detail(entry)
    row.detail:SetText(text)
    row.detail:SetTextColor(unpack(color))

    local status = entry.status
    local quoted = status == Market.CONFIRM
    local confirm = quoted or status == Market.RAISED
    local priced = status == Market.READY or status == Market.POOR or confirm
    row.price:SetShown(priced)
    if priced then row.price:SetText(Money(quoted and entry.quotedTotal or entry.offer.nextCost)) end
    row.price:SetTextColor(unpack(confirm and C.warn or C.text))

    row.button.text:SetText(ButtonText(entry, confirm))
    row.button:SetStyle(confirm and "primary" or "default")
    SidePanel.SetEnabled(row.button, status == Market.READY or confirm)
    PaintStrip(row, fresh)
    local strip = #entry.family.ranks > 1 and STRIP_TOP + STRIP_HEIGHT or 0
    row:SetHeight(SidePanel.HEAD_HEIGHT + strip)
end

local function Paint()
    panel.subtitle:SetText(ns.db.lowerRanks and L.AH_SUBTITLE_LOWER or L.AH_SUBTITLE)
    panel:PaintRows(Market.entries, CreateRow, PaintRow)
    panel.footerText:SetText(string.format(L.AH_TOTAL, Money(Market.Total())))
    panel.footerText:SetShown(#Market.entries > 0)
end

local function Create()
    panel = SidePanel.Create("ReScrollAuctionPanel", {
        title = "AH_TITLE",
        empty = "AH_EMPTY",
        refresh = Market.Refresh,
        toggle = { key = "countBank", label = "COUNT_BANK", desc = "COUNT_BANK_DESC" },
        hosts = HOSTS,
        slot = "auction",
        offset = { x = "auctionX", y = "auctionY" },
        settingsPage = "auction",
    })
end

function AuctionPanel.IsShown()
    return panel ~= nil and panel:IsShown()
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

ns.Listen("MARKET_CHANGED", function()
    if panel and panel:IsShown() then Paint() end
end)

ns.Listen("LOCALE_CHANGED", function()
    if panel and panel:IsShown() then Paint() end
end)
