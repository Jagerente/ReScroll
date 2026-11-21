local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Catalog = ns.Catalog
local Inventory = ns.Inventory

local UtilityBar = { buttons = {} }
ns.UtilityBar = UtilityBar

UtilityBar.PAGE = "scrolls"
UtilityBar.SECTION = "utility"

local PAD = 6
local HEADER_HEIGHT, HEADER_GAP = 14, 5
local HEADER_GLYPH_HEIGHT, HEADER_GLYPH_GAP = 11, 5
local NO_ACTION = "none"
local BORDER = 1
local ICON_CROP = 0.08
local PRESS_INSET = 1
local LABEL_INSET = 3
local SCRIM_ALPHA = 0.85
local HOVER_ALPHA, HOVER_TIME = 0.14, 0.12
local EMPTY_ALPHA = 0.45
local SHOW_TIME = 0.18
local BACKGROUND = { 0.078, 0.076, 0.072 }
local PERCENT = 100
local ICON_BACK = { 0, 0, 0, 0.7 }
local STRATA = "MEDIUM"

local holder, bar, header, glyph, title
local buttons = UtilityBar.buttons
local visible = {}
local barFade = {}
local moving = false
local pendingRefresh = false

local function InCombat()
    return InCombatLockdown()
end

local function UsedRank(family)
    local top = Inventory.TopUsableRank(family, UnitLevel("player")) or family.top
    for index = top.index, 1, -1 do
        local rank = family.ranks[index]
        if Inventory.Count(rank.item) > 0 then return rank end
    end
    return top
end

local function AddLine(text, color)
    GameTooltip:AddLine(text, color[1], color[2], color[3], true)
end

local function ShowTooltip(button)
    local family = button.family
    local have, bank = Inventory.StockCount(family)
    GameTooltip:SetOwner(button, UI.VerticalAnchor(button))
    GameTooltip:SetItemByID(button.rank.item)
    GameTooltip:AddLine(" ")
    AddLine(string.format(L.TIP_STOCK, have, Inventory.StockTarget(family)), have > 0 and C.muted or C.bad)
    if bank > 0 then AddLine(string.format(L.TIP_IN_BANK, bank), C.muted) end
    AddLine(L.TIP_UTILITY, C.muted)
    GameTooltip:Show()
end

local function CountColor(family, have)
    if have == 0 then return C.bad end
    if have < Inventory.StockTarget(family) then return C.warn end
    return C.text
end

local function PaintCooldown(button)
    local start, duration = Inventory.Cooldown(button.rank.item)
    if duration > 0 then
        button.cooldown:SetCooldown(start, duration)
    else
        button.cooldown:Clear()
    end
end

local function PaintButton(button)
    local family = button.family
    local have = Inventory.StockCount(family)
    local count = have > 0 and have or Inventory.Count(button.rank.item)
    button.icon:SetTexture(Catalog.Icon(family, button.rank))
    button.icon:SetDesaturated(count == 0)
    button.art:SetAlpha(count == 0 and EMPTY_ALPHA or 1)
    local shown = ns.db.showCounts
    button.count:SetShown(shown)
    button.scrim:SetShown(shown)
    if shown then
        button.count:SetText(count)
        button.count:SetTextColor(unpack(CountColor(family, have)))
    end
    PaintCooldown(button)
end

local function Paint()
    for _, button in ipairs(visible) do
        PaintButton(button)
    end
end

local function Highlight(button, on)
    UI.Tween(button.hover, on and HOVER_ALPHA or 0, HOVER_TIME, function(_, value) button.highlight:SetAlpha(value) end)
end

local function SavePosition()
    local point, _, _, x, y = holder:GetPoint(1)
    local position = ns.db.utilityPosition
    position.point, position.x, position.y = point, x, y
end

function UtilityBar.ResetPosition()
    local current, default = ns.db.utilityPosition, ns.DEFAULTS.utilityPosition
    current.point, current.x, current.y = default.point, default.x, default.y
    ns.Fire("SETTING_CHANGED", "utilityPosition")
end

local function StartMoving()
    if ns.db.locked or InCombat() then return false end
    moving = true
    GameTooltip:Hide()
    holder:Raise()
    holder:StartMoving()
end

local function StopMoving()
    if not moving then return end
    moving = false
    holder:StopMovingOrSizing()
    SavePosition()
end

local function StartAltMoving()
    if not IsAltKeyDown() then return false end
    return StartMoving()
end

local function OpenSettings()
    ns.Options.Toggle(UtilityBar.PAGE, UtilityBar.SECTION)
end

local function OnHeaderMouseUp(_, mouseButton)
    if mouseButton == "RightButton" then
        OpenSettings()
    elseif mouseButton == "MiddleButton" and not ns.db.locked then
        UtilityBar.ResetPosition()
    end
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
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetDrawEdge(false)
    button.cooldown:SetHideCountdownNumbers(true)

    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    button.highlight = UI.Fill(overlay, { 1, 1, 1, 1 }, "ARTWORK")
    button.highlight:SetPoint("TOPLEFT", BORDER, -BORDER)
    button.highlight:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.highlight:SetAlpha(0)
    button.hover = {}

    button.scrim = overlay:CreateTexture(nil, "BACKGROUND")
    button.scrim:SetColorTexture(1, 1, 1, 1)
    button.scrim:SetGradient("VERTICAL", CreateColor(0, 0, 0, SCRIM_ALPHA), CreateColor(0, 0, 0, 0))
    button.scrim:SetPoint("TOPLEFT", button, "LEFT", BORDER, 0)
    button.scrim:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.count = UI.BoldText(overlay, T.body, C.text)
    button.count:SetPoint("BOTTOMRIGHT", -LABEL_INSET, LABEL_INSET - 1)
end

local function SetPressed(button, pressed)
    local inset = BORDER + (pressed and PRESS_INSET or 0)
    button.icon:SetPoint("TOPLEFT", inset, -inset)
    button.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
end

local function CreateButton()
    local index = #buttons + 1
    local button = CreateFrame("Button", "ReScrollUtility" .. index, bar, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "item")
    button:SetAttribute("*type2", NO_ACTION)
    button:SetAttribute("alt-type1", NO_ACTION)
    button:Hide()
    CreateArt(button)
    W.DragHandle(button, StartAltMoving, StopMoving)
    button:SetScript("PostClick", function(_, mouseButton, down)
        if mouseButton == "RightButton" and not down then OpenSettings() end
    end)
    button:HookScript("OnEnter", function(self)
        Highlight(self, true)
        if self.family then ShowTooltip(self) end
    end)
    button:HookScript("OnLeave", function(self)
        Highlight(self, false)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    button:HookScript("OnMouseDown", function(self) SetPressed(self, true) end)
    button:HookScript("OnMouseUp", function(self) SetPressed(self, false) end)
    button:HookScript("OnHide", function(self) SetPressed(self, false) end)
    buttons[index] = button
    return button
end

local function CreateHeader()
    header = CreateFrame("Frame", nil, bar)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:EnableMouse(true)
    glyph = UI.AddonGlyph(header, HEADER_GLYPH_HEIGHT)
    glyph:SetPoint("LEFT")
    title = UI.BoldText(header, T.label, C.text)
    title:SetPoint("LEFT", glyph, "RIGHT", HEADER_GLYPH_GAP, 0)
    header:SetScript("OnEnter", function(self)
        W.ShowHint(self, ns.db.locked and "HEADER_LOCKED_DESC" or "HEADER_DESC")
    end)
    header:SetScript("OnLeave", W.HideHint)
    header:SetScript("OnMouseUp", OnHeaderMouseUp)
    W.DragHandle(header, StartMoving, StopMoving)
end

local function HeaderWidth()
    return glyph:GetWidth() + HEADER_GLYPH_GAP + math.ceil(title:GetStringWidth())
end

local function FadeBarIn()
    barFade.tweenValue = 0
    bar:SetAlpha(0)
    UI.Tween(barFade, 1, SHOW_TIME, function(_, value) bar:SetAlpha(value) end)
end

local function PaintBackground()
    bar.background:SetAlpha(ns.db.barBackground / PERCENT)
end

local function Create()
    holder = CreateFrame("Frame", "ReScrollUtilityHolder", UIParent)
    holder:SetSize(1, 1)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    holder:SetFrameStrata(STRATA)
    holder:SetToplevel(true)
    holder:Hide()
    holder:HookScript("OnShow", FadeBarIn)

    bar = CreateFrame("Frame", "ReScrollUtilityBar", holder)
    bar:SetPoint("TOPLEFT", holder, "CENTER")
    bar.background = UI.Fill(bar, BACKGROUND)
    PaintBackground()
    CreateHeader()
end

local function PlaceHolder()
    local position = ns.db.utilityPosition
    holder:ClearAllPoints()
    holder:SetPoint(position.point, UIParent, position.point, position.x, position.y)
end

local function Previewing()
    return ns.TestMode.active or ns.Options.IsOpen()
end

local function WantsButton(family, level)
    if not Inventory.Restockable(family, level) then return false end
    if Previewing() or ns.db.utilityVisibility == "always" then return true end
    return ns.db.utilityVisibility == "short" and Inventory.IsShort(family)
end

local function Layout()
    wipe(visible)
    local level = UnitLevel("player")
    for _, family in ipairs(Catalog.utilities) do
        if WantsButton(family, level) then
            local button = buttons[#visible + 1] or CreateButton()
            button.family = family
            button.rank = UsedRank(family)
            button:SetAttribute("item", "item:" .. button.rank.item)
            visible[#visible + 1] = button
        end
    end
    for index = #visible + 1, #buttons do
        buttons[index].family = nil
        buttons[index]:Hide()
    end
    local size, gap = ns.db.iconSize, ns.db.spacing
    local showHeader = ns.db.showHeader
    header:SetShown(showHeader)
    title:SetText(L.UTILITY_HEADER)
    local top = PAD + (showHeader and HEADER_HEIGHT + HEADER_GAP or 0)
    for index, button in ipairs(visible) do
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD + (index - 1) * (size + gap), -top)
        button:Show()
    end
    local count = math.max(1, #visible)
    local width = count * size + (count - 1) * gap
    if showHeader then width = math.max(width, HeaderWidth()) end
    bar:SetSize(PAD * 2 + width, top + size + PAD)
end

local function WantsShown()
    if not ns.db.enabled or #visible == 0 then return false end
    return Previewing() or ns.db.utilityVisibility ~= "never"
end

function UtilityBar.Refresh()
    if not holder then return end
    if InCombat() then
        pendingRefresh = true
        Paint()
        return
    end
    pendingRefresh = false
    Layout()
    holder:SetShown(WantsShown())
    Paint()
end

local function RefreshCooldowns()
    for _, button in ipairs(visible) do PaintCooldown(button) end
end

local function OnCombatEnd()
    StopMoving()
    if pendingRefresh then UtilityBar.Refresh() end
end

for _, message in ipairs({ "INVENTORY_CHANGED", "FAMILIES_CHANGED", "STOCK_CHANGED", "TEST_MODE_CHANGED", "OPTIONS_SHOWN", "LOCALE_CHANGED" }) do
    ns.Listen(message, function() UtilityBar.Refresh() end)
end

ns.Listen("SETTING_CHANGED", function(key)
    if not holder then return end
    if (key == nil or key == "utilityPosition") and not InCombat() then PlaceHolder() end
    if key == nil or key == "barBackground" then PaintBackground() end
    UtilityBar.Refresh()
end)

ns.Listen("LOGIN", function()
    Create()
    PlaceHolder()
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", OnCombatEnd)
    ns.RegisterEvent("PLAYER_LEVEL_UP", function() ns.Schedule("utilityLevel", 0, UtilityBar.Refresh) end)
    ns.RegisterEvent("BAG_UPDATE_COOLDOWN", RefreshCooldowns)
    UtilityBar.Refresh()
end)
