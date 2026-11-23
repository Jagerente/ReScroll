local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local W = ns.Widgets
local Catalog = ns.Catalog
local Inventory = ns.Inventory
local FloatingBar = ns.FloatingBar

local UtilityBar = {}
ns.UtilityBar = UtilityBar

local SETTINGS_PAGE, SETTINGS_SECTION = "scrolls", "utility"
local PAD = FloatingBar.PAD
local EMPTY_ALPHA = 0.45
local SHOW_TIME = 0.18

local floating, holder, bar
local buttons = {}
local visible = {}
local barFade = {}
local pendingRefresh = false

local function UsedRank(family)
    local level = UnitLevel("player")
    return Inventory.OwnedRank(family, level, true) or Inventory.TopUsableRank(family, level) or family.top
end

local function UpdateTooltip(button)
    local family = button.family
    if not family then return end
    local grade = Inventory.StockRank(family)
    GameTooltip:SetOwner(button, UI.VerticalAnchor(button))
    GameTooltip:SetItemByID(button.rank.item)
    FloatingBar.AddTooltipHeader(family)
    FloatingBar.AddStockLines(family, grade)
    if InCombatLockdown() and UsedRank(family) ~= button.rank then W.TooltipLine(L.TIP_AFTER_COMBAT, C.warn) end
    FloatingBar.AddBagLines(family, grade)
    FloatingBar.AddGestureLines(L.TIP_SETTINGS)
    GameTooltip:Show()
end

local function PaintCooldown(button)
    FloatingBar.SetCooldown(button, Inventory.Cooldown(button.rank.item))
end

local function PaintButton(button)
    local family = button.family
    local count, countColor = FloatingBar.ShownCount(family, button.rank)
    button.icon:SetTexture(Catalog.Icon(family, button.rank))
    button.icon:SetDesaturated(count == 0)
    button.art:SetAlpha(count == 0 and EMPTY_ALPHA or 1)
    local shown = ns.db.showCounts
    button.count:SetShown(shown)
    button.scrim:SetShown(shown)
    if shown then
        button.count:SetText(count)
        button.count:SetTextColor(unpack(countColor))
    end
    PaintCooldown(button)
end

local function Paint()
    for _, button in ipairs(visible) do
        PaintButton(button)
    end
end

local function OpenSettings()
    ns.Options.Toggle(SETTINGS_PAGE, SETTINGS_SECTION)
end

local function CreateButton()
    local index = #buttons + 1
    local button = floating:CreateButton("ReScrollUtility" .. index)
    button:SetAttribute("type", "item")
    button:HookScript("PostClick", function(_, mouseButton)
        if mouseButton == "RightButton" then OpenSettings() end
    end)
    button.UpdateTooltip = UpdateTooltip
    button:HookScript("OnEnter", UpdateTooltip)
    buttons[index] = button
    return button
end

local function FadeBarIn()
    barFade.tweenValue = 0
    bar:SetAlpha(0)
    UI.Tween(barFade, 1, SHOW_TIME, function(_, value) bar:SetAlpha(value) end)
end

local function AnchorBar(frame, anchor)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "CENTER")
end

local function Create()
    floating = FloatingBar.Create({
        holderName = "ReScrollUtilityHolder",
        barName = "ReScrollUtilityBar",
        positionKey = "utilityPosition",
        anchorBar = AnchorBar,
        onSettings = OpenSettings,
    })
    UtilityBar.floating = floating
    holder, bar = floating.holder, floating.bar
    holder:Hide()
    holder:HookScript("OnShow", FadeBarIn)
    floating:Place()
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
    floating:PaintHeader("UTILITY_HEADER")
    local top = floating:RowTop()
    for index, button in ipairs(visible) do
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD + (index - 1) * (size + gap), -top)
        button:Show()
    end
    local count = math.max(1, #visible)
    local width = count * size + (count - 1) * gap
    if ns.db.showHeader then width = math.max(width, floating:HeaderWidth()) end
    bar:SetSize(PAD * 2 + width, top + size + PAD)
end

local function WantsShown()
    if not ns.db.enabled or #visible == 0 then return false end
    return Previewing() or ns.db.utilityVisibility ~= "never"
end

function UtilityBar.Refresh()
    if not holder then return end
    if InCombatLockdown() then
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

for _, message in ipairs({ "INVENTORY_CHANGED", "FAMILIES_CHANGED", "STOCK_CHANGED", "TEST_MODE_CHANGED", "OPTIONS_SHOWN", "LOCALE_CHANGED", "SETTING_CHANGED" }) do
    ns.Listen(message, function() UtilityBar.Refresh() end)
end

ns.Listen("LOGIN", function()
    Create()
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if pendingRefresh then UtilityBar.Refresh() end
    end)
    ns.RegisterEvent("PLAYER_LEVEL_UP", function() ns.Schedule("utilityLevel", 0, UtilityBar.Refresh) end)
    ns.RegisterEvent("BAG_UPDATE_COOLDOWN", RefreshCooldowns)
    UtilityBar.Refresh()
end)
