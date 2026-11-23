local _, ns = ...

local UI = ns.UI
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Inventory = ns.Inventory

local FloatingBar = {}
ns.FloatingBar = FloatingBar

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
local ICON_BACK = { 0, 0, 0, 0.7 }
local BACKGROUND = { C.window[1], C.window[2], C.window[3] }
local STRATA = "MEDIUM"
local PERCENT = 100

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

function FloatingBar.CountColor(family, have)
    if have == 0 then return C.bad end
    if have < Inventory.StockTarget(family) then return C.warn end
    return C.text
end

function FloatingBar.SetCooldown(button, start, duration)
    if duration > 0 then
        button.cooldown:SetCooldown(start, duration)
    else
        button.cooldown:Clear()
    end
end

local function SetPressed(button, pressed)
    local inset = BORDER + (pressed and PRESS_INSET or 0)
    button.icon:SetPoint("TOPLEFT", inset, -inset)
    button.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
end

local function Highlight(button, on)
    UI.Tween(button.hover, on and HOVER_ALPHA or 0, HOVER_TIME, function(_, value) button.highlight:SetAlpha(value) end)
end

local function CreateArt(button)
    button.art = CreateFrame("Frame", nil, button)
    button.art:SetAllPoints()
    UI.Fill(button.art, ICON_BACK)
    button.icon = button.art:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    SetPressed(button, false)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
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

function BarMixin:CreateButton(name)
    local button = CreateFrame("Button", name, self.bar, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("*type2", NO_ACTION)
    button:SetAttribute("alt-type1", NO_ACTION)
    button:Hide()
    CreateArt(button)
    W.DragHandle(button, function()
        if not IsAltKeyDown() then return false end
        return self:StartMoving()
    end, function() self:StopMoving() end)
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

local function CreateHeader(panel, opts)
    local header = CreateFrame("Frame", nil, panel.bar)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:EnableMouse(true)
    panel.glyph = UI.AddonGlyph(header, HEADER_GLYPH_HEIGHT)
    panel.glyph:SetPoint("LEFT")
    panel.title = UI.BoldText(header, T.label, C.text)
    panel.title:SetPoint("LEFT", panel.glyph, "RIGHT", HEADER_GLYPH_GAP, 0)
    header:SetScript("OnEnter", function(self)
        W.ShowHint(self, ns.db.locked and "HEADER_LOCKED_DESC" or opts.hint)
    end)
    header:SetScript("OnLeave", W.HideHint)
    header:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            opts.onSettings()
        elseif button == "MiddleButton" and not ns.db.locked then
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
    CreateHeader(panel, opts)

    ns.Listen("SETTING_CHANGED", function(key)
        if key == nil or key == "barBackground" then panel:PaintBackground() end
        if key == nil or key == panel.positionKey then panel:Place() end
    end)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() panel:StopMoving() end)
    return panel
end
