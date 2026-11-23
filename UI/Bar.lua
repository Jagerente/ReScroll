local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Status = ns.Status
local Inventory = ns.Inventory
local Catalog = ns.Catalog
local FloatingBar = ns.FloatingBar

local Bar = {}
ns.Bar = Bar

Bar.APPLY_BUTTON = "ReScrollApplyButton"
Bar.BINDING = "CLICK " .. Bar.APPLY_BUTTON .. ":LeftButton"

local APPLY_PANEL_BUTTON = "ReScrollApplyPanelButton"
local PAD = FloatingBar.PAD
local APPLY_TEXT_PAD, APPLY_MIN_WIDTH = 12, 64
local BORDER, LABEL_INSET = FloatingBar.BORDER, FloatingBar.LABEL_INSET
local PRESS_INSET = 1
local DOT_SIZE = 9
local MOVE_TIME, FADE_TIME, SHOW_TIME = 0.2, 0.15, 0.18
local EMPTY_ALPHA, GROUP_ALPHA = 0.45, 0.7
local TIMER_INTERVAL = 1
local READY_CHECK_SECONDS = 40
local CONTROL_DELAY = 0.5
local PULSE_ALPHA, PULSE_TIME, PULSE_LOOPS = 0.55, 0.35, 3
local GLOW_OUTSET = 2

local floating, holder, bar, applyButton, applyKeyButton, glow, pulse
local slots = {}
local visible = {}
local layoutMotion = {}
local barFade = {}
local timerTicker
local pendingRefresh = false
local readyUntil = 0
local shown = false

local RomanRank = Catalog.RomanRank
local TooltipLine = W.TooltipLine

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 60 then
        return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
    end
    return tostring(seconds)
end

local function Records()
    if ns.TestMode.active then return ns.TestMode.records, ns.TestMode.chain end
    return Status.records, Status.chain
end

local function SetAction(button, record)
    if ns.TestMode.active or not record then
        button:SetAttribute("type", nil)
        return
    end
    if record.spell then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", record.spell)
        button:SetAttribute("item", nil)
    elseif record.rank then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. record.rank.item)
        button:SetAttribute("spell", nil)
    else
        button:SetAttribute("type", nil)
    end
end

local function NoteUse(record)
    if record and record.rank and not record.spell and not ns.TestMode.active then
        ns.Learning.NoteUse(record.family)
    end
end

local function AddStatusLine(record)
    local state = record.state
    if state == Status.EXPIRING and not record.rank then
        TooltipLine(L.TIP_NO_REFRESH, C.warn)
    elseif state == Status.UPGRADE then
        local active, stronger = UI.Colored(RomanRank(record.activeRank), C.text), UI.Colored(RomanRank(record.rank), C.text)
        TooltipLine(string.format(L.TIP_UPGRADE, active, stronger), C.muted)
    elseif state == Status.GROUP then
        local provider = record.provider
        local name = UI.Colored(provider.name or "?", { UI.ClassColor(provider.class) })
        TooltipLine(string.format(L.TIP_GROUP, name), C.muted)
    end
end

local function AddScrollLines(record)
    local family = record.family
    local grade = Inventory.StockRank(family)
    FloatingBar.AddStockLines(family, grade)
    AddStatusLine(record)
    FloatingBar.AddBagLines(family, grade)
end

local function ShowRecordTooltip(owner, record)
    GameTooltip:SetOwner(owner, UI.VerticalAnchor(owner))
    if record.spell then
        GameTooltip:SetSpellByID(record.spell)
        FloatingBar.AddTooltipHeader(record.family)
    else
        GameTooltip:SetItemByID((record.rank or record.top).item)
        FloatingBar.AddTooltipHeader(record.family)
        AddScrollLines(record)
    end
    FloatingBar.AddGestureLines(not ns.TestMode.active and L.TIP_HIDE_ZONE or nil)
    GameTooltip:Show()
end

local function UpdateSlotTooltip(slot)
    if slot.record then ShowRecordTooltip(slot, slot.record) end
end

local function PaintCooldown(slot)
    local record = slot.record
    if not record then return end
    local start, duration = 0, 0
    if record.spell then
        local info = C_Spell.GetSpellCooldown(record.spell)
        if info and not ns.IsSecret(info.startTime) and not ns.IsSecret(info.duration) then
            start, duration = info.startTime, info.duration
        end
    elseif record.rank then
        start, duration = Inventory.Cooldown(record.rank.item)
    end
    FloatingBar.SetCooldown(slot, start, duration)
end

local function PaintTimer(slot)
    local record = slot.record
    if record and record.state == Status.EXPIRING then
        slot.timer:SetText(FormatTime(record.expiration - GetTime()))
        slot.timer:Show()
        slot.timerScrim:Show()
    else
        slot.timer:Hide()
        slot.timerScrim:Hide()
    end
end

local function PaintSlot(slot)
    local record = slot.record
    local state = record.state
    local rank = record.rank or record.top
    if record.spell then
        slot.icon:SetTexture(C_Spell.GetSpellTexture(record.spell))
    else
        slot.icon:SetTexture(Catalog.Icon(record.family, rank))
    end
    local dim = state == Status.EMPTY or state == Status.GROUP
    slot.icon:SetDesaturated(dim)
    slot.art:SetAlpha(state == Status.EMPTY and EMPTY_ALPHA or state == Status.GROUP and GROUP_ALPHA or 1)

    slot.rankText:SetShown(not record.spell and #record.family.ranks > 1)
    slot.rankText:SetText(RomanRank(rank))
    slot.rankText:SetTextColor(unpack(state == Status.UPGRADE and C.good or C.text))

    local count, countColor
    if not record.spell then count, countColor = FloatingBar.ShownCount(record.family, rank) end
    slot.count:SetShown(count ~= nil and ns.db.showCounts)
    if count then
        slot.count:SetText(count)
        slot.count:SetTextColor(unpack(countColor))
    end

    slot.scrim:SetShown(slot.rankText:IsShown() or slot.count:IsShown())

    local provider = state == Status.GROUP and record.provider or nil
    slot.dot:SetShown(provider ~= nil)
    if provider then slot.dot:SetVertexColor(UI.ClassColor(provider.class)) end

    PaintTimer(slot)
    PaintCooldown(slot)
end

local function OnPanelPreClick(self, mouseButton)
    if mouseButton == "LeftButton" and not IsAltKeyDown() then NoteUse(self.record) end
end

local function OnKeyPreClick(self, _, down)
    if down then NoteUse(self.record) end
end

local function CreateSlot(index)
    local slot = floating:CreateButton("ReScrollSlot" .. index)
    slot:SetAttribute("unit", "player")
    slot:SetAlpha(0)
    local overlay = slot.overlay
    slot.rankText = UI.BoldText(overlay, T.caption, C.text)
    slot.rankText:SetPoint("BOTTOMLEFT", LABEL_INSET, LABEL_INSET)
    slot.timerScrim = FloatingBar.Scrim(overlay, true)
    slot.timerScrim:SetPoint("TOPLEFT", BORDER, -BORDER)
    slot.timerScrim:SetPoint("BOTTOMRIGHT", slot, "RIGHT", -BORDER, 0)
    slot.timerScrim:Hide()
    slot.timer = UI.BoldText(overlay, T.body, C.warn)
    slot.timer:SetPoint("TOP", 0, -LABEL_INSET)
    slot.dot = W.Circle(overlay, "OVERLAY")
    slot.dot:SetSize(DOT_SIZE, DOT_SIZE)
    slot.dot:SetPoint("TOPRIGHT", -3, -3)

    slot.fade = {}
    slot:SetScript("PreClick", OnPanelPreClick)
    slot:HookScript("PostClick", function(self, button)
        if button == "RightButton" and self.record and not ns.TestMode.active and not InCombatLockdown() then
            Status.Snooze(self.record.family)
        end
    end)
    slot.UpdateTooltip = UpdateSlotTooltip
    slot:HookScript("OnEnter", UpdateSlotTooltip)
    slots[index] = slot
    return slot
end

local function PaintApply(chain)
    local upcoming = chain[1]
    applyButton.record, applyKeyButton.record = upcoming, upcoming
    SetAction(applyButton, upcoming)
    SetAction(applyKeyButton, upcoming)
    applyButton.label:SetText(L.APPLY)
    local width = math.ceil(applyButton.label:GetStringWidth()) + APPLY_TEXT_PAD * 2
    applyButton:SetSize(math.max(APPLY_MIN_WIDTH, width), ns.db.iconSize)
end

local function CreateApplyKeyButton()
    applyKeyButton = CreateFrame("Button", Bar.APPLY_BUTTON, UIParent, "SecureActionButtonTemplate")
    applyKeyButton:RegisterForClicks("AnyUp", "AnyDown")
    applyKeyButton:SetAttribute("unit", "player")
    applyKeyButton:SetScript("PreClick", OnKeyPreClick)
end

local function CreateApplyButton()
    applyButton = CreateFrame("Button", APPLY_PANEL_BUTTON, bar, "SecureActionButtonTemplate")
    applyButton:SetAttribute("unit", "player")
    floating:BindMouse(applyButton)
    local fill = applyButton:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    W.HoverFill(applyButton, fill, C.accent, C.accentHover)
    applyButton.label = UI.BoldText(applyButton, T.label, C.onAccent)
    applyButton.label:SetPoint("CENTER")
    applyButton.fade = {}
    applyButton:SetScript("PreClick", OnPanelPreClick)
    applyButton:HookScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 0, -PRESS_INSET) end)
    applyButton:HookScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
end

local function CreatePulse()
    glow = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetColorTexture(unpack(C.accent))
    glow:SetPoint("TOPLEFT", -GLOW_OUTSET, GLOW_OUTSET)
    glow:SetPoint("BOTTOMRIGHT", GLOW_OUTSET, -GLOW_OUTSET)
    glow:SetAlpha(0)
    pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(PULSE_ALPHA)
    fade:SetDuration(PULSE_TIME)
    fade:SetSmoothing("IN_OUT")
    local loops = 0
    pulse:SetScript("OnLoop", function(self)
        loops = loops + 1
        if loops >= PULSE_LOOPS * 2 then
            loops = 0
            self:Stop()
        end
    end)
end

local function AnchorBar(frame, anchor)
    frame:ClearAllPoints()
    local grow = ns.db.grow
    if grow == "LEFT" then
        frame:SetPoint("TOPRIGHT", anchor, "CENTER")
    elseif grow == "CENTER" then
        frame:SetPoint("TOP", anchor, "CENTER")
    else
        frame:SetPoint("TOPLEFT", anchor, "CENTER")
    end
end

local function Create()
    floating = FloatingBar.Create({
        holderName = "ReScrollHolder",
        barName = "ReScrollBar",
        positionKey = "position",
        anchorBar = AnchorBar,
        onSettings = function() ns.Options.Toggle() end,
    })
    Bar.floating = floating
    holder, bar = floating.holder, floating.bar
    RegisterStateDriver(holder, "visibility", "[combat] hide; show")
    bar:Hide()
    bar:SetAlpha(0)
    CreatePulse()
    CreateApplyButton()
    CreateApplyKeyButton()
    for index = 1, #ns.FAMILIES do
        CreateSlot(index)
    end
    floating:Place()
end

local function ApplyLayout(_, t)
    for _, slot in ipairs(visible) do
        slot.x = UI.Lerp(slot.fromX, slot.toX, t)
        slot.y = UI.Lerp(slot.fromY, slot.toY, t)
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", bar, "TOPLEFT", slot.x, -slot.y)
    end
    bar:SetWidth(UI.Lerp(bar.fromWidth, bar.toWidth, t))
    bar:SetHeight(UI.Lerp(bar.fromHeight, bar.toHeight, t))
end

local function FadeSlot(slot, alpha, done)
    UI.Tween(slot.fade, alpha, FADE_TIME, function(_, value) slot:SetAlpha(value) end, done)
end

local function HideSlot(slot)
    if not slot:IsShown() then return end
    slot.leaving = true
    FadeSlot(slot, 0, function()
        if slot.leaving and not InCombatLockdown() then
            slot.leaving = false
            slot:Hide()
        end
    end)
end

local function ShowSlot(slot, x, y)
    slot.leaving = false
    if not slot:IsShown() then
        slot.fade.tweenValue = 0
        slot:SetAlpha(0)
        slot.x, slot.y = x, y
        slot:Show()
    end
    FadeSlot(slot, 1)
end

local function Animate(owner, animate, apply)
    if animate then
        owner.tweenValue = 0
        UI.Tween(owner, 1, MOVE_TIME, apply)
    else
        UI.SnapTween(owner, 1, apply)
    end
end

local function Layout(animate)
    local records, chain = Records()
    local size, gap = ns.db.iconSize, ns.db.spacing
    floating:PaintHeader("HEADER")
    PaintApply(chain)

    wipe(visible)
    local top, left = floating:RowTop(), PAD
    local hasApply = #chain > 0
    applyButton:SetShown(hasApply)
    if hasApply then
        applyButton:ClearAllPoints()
        applyButton:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -top)
        left = left + applyButton:GetWidth() + gap
    end
    local perRow, step = ns.db.perRow, size + gap
    for index, slot in ipairs(slots) do
        local record = records[index]
        slot.record = record
        if record then
            local column = #visible % perRow
            local x, y = left + column * step, top + math.floor(#visible / perRow) * step
            slot:SetSize(size, size)
            SetAction(slot, Status.CanUse(record) and record or nil)
            PaintSlot(slot)
            ShowSlot(slot, x, y)
            slot.fromX, slot.fromY = slot.x or x, slot.y or y
            slot.toX, slot.toY = x, y
            visible[#visible + 1] = slot
        else
            SetAction(slot, nil)
            HideSlot(slot)
        end
    end
    local columns = math.min(#visible, perRow)
    local lines = math.max(1, math.ceil(#visible / perRow))
    local width = math.max(left + columns * step - gap + PAD, PAD * 2 + APPLY_MIN_WIDTH)
    local height = top + lines * step - gap + PAD
    bar.fromWidth = bar:GetWidth() > 0 and bar:GetWidth() or width
    bar.fromHeight = bar:GetHeight() > 0 and bar:GetHeight() or height
    bar.toWidth, bar.toHeight = width, height
    Animate(layoutMotion, animate, ApplyLayout)
end

local function InContext()
    local visibility = ns.db.visibility
    if visibility == "always" then return true end
    if visibility == "group" then
        return IsInGroup() or (IsInInstance())
    end
    return false
end

local function ShowsOnReadyCheck()
    return ns.db.readyCheck or ns.db.visibility == "readycheck"
end

local function WantShown()
    if ns.TestMode.active then return true end
    if not ns.db.enabled then return false end
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return false end
    if #Status.records == 0 then return false end
    if ns.Options.IsOpen() then return true end
    if Status.needed == 0 then return false end
    if GetTime() < readyUntil then return true end
    if ns.db.hideResting and IsResting() then return false end
    return InContext()
end

local function UpdateTimerTicker()
    local need = false
    if shown then
        for _, slot in ipairs(visible) do
            if slot.record.state == Status.EXPIRING then need = true end
        end
    end
    if need and not timerTicker then
        timerTicker = C_Timer.NewTicker(TIMER_INTERVAL, function()
            for _, slot in ipairs(visible) do PaintTimer(slot) end
        end)
    elseif not need and timerTicker then
        timerTicker:Cancel()
        timerTicker = nil
    end
end

local function ApplyBarAlpha(_, value)
    bar:SetAlpha(value)
end

local function SetBarShown(want)
    if want == shown then return end
    shown = want
    if want then
        if not bar:IsShown() then
            barFade.tweenValue = 0
            bar:SetAlpha(0)
            bar:Show()
        end
        UI.Tween(barFade, 1, SHOW_TIME, ApplyBarAlpha)
    else
        UI.Tween(barFade, 0, SHOW_TIME, ApplyBarAlpha, function()
            if not shown and not InCombatLockdown() then bar:Hide() end
        end)
    end
end

local function FinishHiding()
    if not shown and bar:IsShown() then
        UI.StopTween(barFade)
        bar:Hide()
    end
    for _, slot in ipairs(slots) do
        if slot.leaving then
            slot.leaving = false
            UI.StopTween(slot.fade)
            slot:Hide()
        end
    end
end

function Bar.Refresh(animate)
    if not holder then return end
    if InCombatLockdown() then
        pendingRefresh = true
        return
    end
    pendingRefresh = false
    local want = WantShown()
    Layout(animate and shown and want)
    SetBarShown(want)
    UpdateTimerTicker()
end

local function RefreshAnimated()
    Bar.Refresh(true)
end

local function RefreshAfterControl()
    ns.Schedule("control", CONTROL_DELAY, RefreshAnimated)
end

local function RefreshCooldowns()
    if not shown then return end
    for _, slot in ipairs(visible) do PaintCooldown(slot) end
end

local function OnReadyCheck()
    if not ShowsOnReadyCheck() then return end
    readyUntil = GetTime() + READY_CHECK_SECONDS
    C_Timer.After(READY_CHECK_SECONDS + 0.1, RefreshAnimated)
    RefreshAnimated()
    if shown then
        pulse:Stop()
        pulse:Play()
    end
end

local function OnCombatStart()
    UI.StopTween(layoutMotion)
    for _, slot in ipairs(slots) do UI.StopTween(slot.fade) end
end

ns.Listen("STATUS_CHANGED", RefreshAnimated)
ns.Listen("TEST_MODE_CHANGED", RefreshAnimated)
ns.Listen("OPTIONS_SHOWN", RefreshAnimated)
ns.Listen("LOCALE_CHANGED", function() Bar.Refresh(false) end)
ns.Listen("SETTING_CHANGED", function(key)
    if not holder then return end
    if key == "grow" then floating:Place() end
    Bar.Refresh(false)
end)

ns.Listen("LOGIN", function()
    Create()
    ns.RegisterEvent("PLAYER_DEAD", RefreshAnimated)
    ns.RegisterEvent("PLAYER_ALIVE", RefreshAnimated)
    ns.RegisterEvent("PLAYER_UNGHOST", RefreshAnimated)
    ns.RegisterEvent("PLAYER_UPDATE_RESTING", RefreshAnimated)
    ns.RegisterEvent("PLAYER_CONTROL_LOST", RefreshAfterControl)
    ns.RegisterEvent("PLAYER_CONTROL_GAINED", RefreshAfterControl)
    ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", RefreshAnimated)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", RefreshAnimated)
    ns.RegisterEvent("GROUP_ROSTER_UPDATE", RefreshAnimated)
    ns.RegisterEvent("PLAYER_REGEN_DISABLED", OnCombatStart)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        FinishHiding()
        if pendingRefresh then Bar.Refresh(false) end
    end)
    ns.RegisterEvent("READY_CHECK", OnReadyCheck)
    ns.RegisterEvent("BAG_UPDATE_COOLDOWN", RefreshCooldowns)
    ns.RegisterEvent("SPELL_UPDATE_COOLDOWN", RefreshCooldowns)
    Bar.Refresh(false)
end)
