local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Catalog = ns.Catalog
local Inventory = ns.Inventory

local FloatingBar = {}
ns.FloatingBar = FloatingBar

local PAD = 4
local HEADER_HEIGHT, HEADER_GAP = 14, 5
local HEADER_GLYPH_HEIGHT, HEADER_GLYPH_GAP = 11, 5
local NO_ACTION = "none"
local ALT_CLICKS = { "alt-type1", "alt-shift-type1", "alt-ctrl-type1", "alt-ctrl-shift-type1" }
local BORDER = 1
local ICON_CROP = 0.08
local PRESS_INSET = 1
local LABEL_INSET = 3
local SCRIM_ALPHA = 0.85
local HOVER_ALPHA, HOVER_TIME = 0.14, 0.12
local ICON_BACK = { 0, 0, 0, 0.7 }
local BACKGROUND = { C.window[1], C.window[2], C.window[3] }
local STRATA = "MEDIUM"
local PERCENT = 100
local TIP_GLYPH_HEIGHT = 14
local TIP_GLYPH = UI.InlineGlyph(TIP_GLYPH_HEIGHT)
local TIP_GAP = " "
local TIP_LIST_MIN_KINDS = 2

FloatingBar.PAD = PAD
FloatingBar.LABEL_INSET = LABEL_INSET
FloatingBar.BORDER = BORDER

function FloatingBar.Scrim(parent, fromTop)
    local scrim = parent:CreateTexture(nil, "BACKGROUND")
    scrim:SetColorTexture(1, 1, 1, 1)
    local dark, clear = CreateColor(0, 0, 0, SCRIM_ALPHA), CreateColor(0, 0, 0, 0)
    if fromTop then
        scrim:SetGradient("VERTICAL", clear, dark)
    else
        scrim:SetGradient("VERTICAL", dark, clear)
    end
    return scrim
end

local function CountColor(family, have, fullColor)
    if have == 0 then return C.bad end
    if have < Inventory.StockTarget(family) then return C.warn end
    return fullColor or C.text
end

function FloatingBar.ShownCount(family, rank)
    local inBags = Inventory.Count(rank.item)
    if Inventory.StockTarget(family) == 0 then return inBags, inBags > 0 and C.text or C.bad end
    local kept = Inventory.StockCount(family)
    return kept > 0 and kept or inBags, CountColor(family, kept)
end

local function AddRow(left, right, leftColor, rightColor)
    GameTooltip:AddDoubleLine(left, right, leftColor[1], leftColor[2], leftColor[3], rightColor[1], rightColor[2], rightColor[3])
end

local function AddGap()
    GameTooltip:AddLine(TIP_GAP)
end

function FloatingBar.AddTooltipHeader(family)
    AddGap()
    AddRow(TIP_GLYPH .. " " .. ns.TITLE, Catalog.Name(family), C.accent, C.text)
end

function FloatingBar.AddStockLines(family, grade)
    if Inventory.StockTarget(family) == 0 then return end
    local have, bank = Inventory.StockCount(family, grade)
    local count = UI.Colored(have, CountColor(family, have, C.good))
    AddRow(L.TIP_STOCK, string.format(L.TIP_STOCK_VALUE, count, Inventory.StockTarget(family)), C.muted, C.muted)
    if bank > 0 then AddRow(L.TIP_IN_BANK, bank, C.muted, C.text) end
end

local owned, offered = {}, {}

local function RanksInBags(family)
    wipe(owned)
    for _, rank in ipairs(Inventory.OfferRanks(family, UnitLevel("player"), offered)) do
        if Inventory.Count(rank.item) > 0 then owned[#owned + 1] = rank end
    end
    return owned
end

local function NamesCountedRanks(family, grade, ranks)
    if not grade or #family.ranks < 2 then return false end
    if grade ~= Inventory.TopUsableRank(family, UnitLevel("player")) then return true end
    local lowest = ranks[#ranks]
    return lowest ~= nil and lowest.index < grade.index
end

local function RankLabel(family, rank)
    local name = Catalog.RankName(family, rank)
    if family.utility then return name end
    return name .. " " .. UI.Colored(string.format(L.STAT_BONUS, rank.amount), C.faint)
end

function FloatingBar.AddBagLines(family, grade)
    local stocked = Inventory.StockTarget(family) > 0
    local ranks = RanksInBags(family)
    local listed = #ranks >= TIP_LIST_MIN_KINDS
    if listed then AddGap() end
    if stocked and NamesCountedRanks(family, grade, ranks) then
        W.TooltipLine(string.format(L.TIP_STOCK_FROM, UI.Colored(Catalog.RomanRank(grade), C.text)), C.faint)
    end
    if not listed then return end
    for _, rank in ipairs(ranks) do
        local counted = not stocked or (grade and rank.index >= grade.index)
        local color = counted and C.text or C.faint
        AddRow(RankLabel(family, rank), string.format(L.COUNT, Inventory.Count(rank.item)), color, color)
    end
end

function FloatingBar.AddGestureLines(rightClick)
    local canMove = not ns.db.locked and not InCombatLockdown()
    if not canMove and not rightClick then return end
    AddGap()
    if canMove then AddRow(L.TIP_ALT_DRAG, L.TIP_MOVE, C.accent, C.text) end
    if rightClick then AddRow(L.TIP_RIGHT_CLICK, rightClick, C.accent, C.text) end
end

function FloatingBar.SetCooldown(button, start, duration)
    if duration > 0 then
        button.cooldown:SetCooldown(start, duration)
    else
        button.cooldown:Clear()
    end
end

local function SetPressed(button, pressed)
    local inset = pressed and PRESS_INSET or 0
    button.art:SetPoint("TOPLEFT", inset, -inset)
    button.art:SetPoint("BOTTOMRIGHT", -inset, inset)
end

local function Highlight(button, on)
    UI.Tween(button.hover, on and HOVER_ALPHA or 0, HOVER_TIME, function(_, value) button.highlight:SetAlpha(value) end)
end

local function CreateArt(button)
    button.art = CreateFrame("Frame", nil, button)
    button.art:SetAllPoints()
    UI.Fill(button.art, ICON_BACK)
    button.icon = button.art:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", BORDER, -BORDER)
    button.icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.art)
    button.cooldown:SetDrawEdge(false)
    button.cooldown:SetHideCountdownNumbers(true)

    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    button.overlay = overlay
    button.highlight = UI.Fill(overlay, { 1, 1, 1, 1 }, "ARTWORK")
    button.highlight:SetPoint("TOPLEFT", BORDER, -BORDER)
    button.highlight:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.highlight:SetAlpha(0)
    button.hover = {}

    button.scrim = FloatingBar.Scrim(overlay, false)
    button.scrim:SetPoint("TOPLEFT", button, "LEFT", BORDER, 0)
    button.scrim:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.count = UI.BoldText(overlay, T.body, C.text)
    button.count:SetPoint("BOTTOMRIGHT", -LABEL_INSET, LABEL_INSET - 1)
end

local BarMixin = {}

function BarMixin:Place()
    if InCombatLockdown() then return end
    local position = ns.db[self.positionKey]
    self.holder:ClearAllPoints()
    self.holder:SetPoint(position.point, UIParent, position.point, position.x, position.y)
    self.anchorBar(self.bar, self.holder)
end

function BarMixin:ResetPosition()
    local position, default = ns.db[self.positionKey], ns.DEFAULTS[self.positionKey]
    position.point, position.x, position.y = default.point, default.x, default.y
    ns.Fire("SETTING_CHANGED", self.positionKey)
end

function BarMixin:StartMoving()
    if ns.db.locked or InCombatLockdown() then return false end
    self.moving = true
    GameTooltip:Hide()
    self.holder:Raise()
    self.holder:StartMoving()
end

function BarMixin:StopMoving()
    if not self.moving then return end
    self.moving = false
    self.holder:StopMovingOrSizing()
    local point, _, _, x, y = self.holder:GetPoint(1)
    local position = ns.db[self.positionKey]
    position.point, position.x, position.y = point, x, y
end

function BarMixin:RowTop()
    return PAD + (ns.db.showHeader and HEADER_HEIGHT + HEADER_GAP or 0)
end

function BarMixin:HeaderWidth()
    return self.glyph:GetWidth() + HEADER_GLYPH_GAP + math.ceil(self.title:GetStringWidth())
end

function BarMixin:PaintHeader(titleKey)
    self.header:SetShown(ns.db.showHeader)
    self.title:SetText(ns.L[titleKey])
end

function BarMixin:PaintBackground()
    self.bar.background:SetAlpha(ns.db.barBackground / PERCENT)
end

local function IgnoreDrag() end

function BarMixin:BindMouse(button)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", IgnoreDrag)
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("*type2", NO_ACTION)
    button:SetAttribute("*type3", NO_ACTION)
    for _, attribute in ipairs(ALT_CLICKS) do
        button:SetAttribute(attribute, NO_ACTION)
    end
    W.DragHandle(button, function()
        if not IsAltKeyDown() then return false end
        return self:StartMoving()
    end, function() self:StopMoving() end)
    button:HookScript("PostClick", function(_, mouseButton)
        if mouseButton == "MiddleButton" and not ns.db.locked and not InCombatLockdown() then self:ResetPosition() end
    end)
end

function BarMixin:CreateButton(name)
    local button = CreateFrame("Button", name, self.bar, "SecureActionButtonTemplate")
    button:Hide()
    CreateArt(button)
    self:BindMouse(button)
    button:HookScript("OnEnter", function(b) Highlight(b, true) end)
    button:HookScript("OnLeave", function(b)
        Highlight(b, false)
        if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
    end)
    button:HookScript("OnMouseDown", function(b) SetPressed(b, true) end)
    button:HookScript("OnMouseUp", function(b) SetPressed(b, false) end)
    button:HookScript("OnHide", function(b) SetPressed(b, false) end)
    return button
end

local function HeaderHint()
    if ns.db.locked then return "HEADER_LOCKED_DESC" end
    return InCombatLockdown() and "HEADER_COMBAT_DESC" or "HEADER_DESC"
end

local function CreateHeader(panel, onSettings)
    local header = CreateFrame("Frame", nil, panel.bar)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:EnableMouse(true)
    panel.glyph = UI.AddonGlyph(header, HEADER_GLYPH_HEIGHT)
    panel.glyph:SetPoint("LEFT")
    panel.title = UI.BoldText(header, T.label, C.text)
    panel.title:SetPoint("LEFT", panel.glyph, "RIGHT", HEADER_GLYPH_GAP, 0)
    header:SetScript("OnEnter", function(self) W.ShowHint(self, HeaderHint()) end)
    header:SetScript("OnLeave", W.HideHint)
    header:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            onSettings()
        elseif button == "MiddleButton" and not ns.db.locked and not InCombatLockdown() then
            panel:ResetPosition()
        end
    end)
    W.DragHandle(header, function() return panel:StartMoving() end, function() panel:StopMoving() end)
    panel.header = header
end

function FloatingBar.Create(opts)
    local panel = Mixin({ positionKey = opts.positionKey, anchorBar = opts.anchorBar, moving = false }, BarMixin)
    local holder = CreateFrame("Frame", opts.holderName, UIParent)
    holder:SetSize(1, 1)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    holder:SetFrameStrata(STRATA)
    holder:SetToplevel(true)
    panel.holder = holder

    local bar = CreateFrame("Frame", opts.barName, holder)
    bar.background = UI.Fill(bar, BACKGROUND)
    panel.bar = bar
    panel:PaintBackground()
    CreateHeader(panel, opts.onSettings)

    ns.Listen("SETTING_CHANGED", function(key)
        if key == nil or key == "barBackground" then panel:PaintBackground() end
        if key == nil or key == panel.positionKey then panel:Place() end
    end)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() panel:StopMoving() end)
    return panel
end
