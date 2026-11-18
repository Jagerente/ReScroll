local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Status = ns.Status
local Inventory = ns.Inventory
local Catalog = ns.Catalog

local Bar = {}
ns.Bar = Bar

Bar.APPLY_BUTTON = "ReScrollApplyButton"
Bar.BINDING = "CLICK " .. Bar.APPLY_BUTTON .. ":LeftButton"

local PAD = 6
local HEADER_HEIGHT, HEADER_GAP = 14, 5
local HEADER_GLYPH_HEIGHT, HEADER_GLYPH_GAP = 11, 5
local NO_ACTION = "none"
local APPLY_TEXT_PAD, APPLY_MIN_WIDTH = 12, 64
local SCRIM_ALPHA = 0.85
local LABEL_INSET = 3
local ICON_CROP = 0.08
local BORDER = 1
local PRESS_INSET = 1
local DOT_SIZE = 9
local MOVE_TIME, FADE_TIME, SHOW_TIME = 0.2, 0.15, 0.18
local HOVER_ALPHA = 0.14
local EMPTY_ALPHA, GROUP_ALPHA = 0.45, 0.7
local TIMER_INTERVAL = 1
local READY_CHECK_SECONDS = 40
local CONTROL_DELAY = 0.5
local PULSE_ALPHA, PULSE_TIME, PULSE_LOOPS = 0.55, 0.35, 3
local GLOW_OUTSET = 2
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }
local BACKGROUND = { 0.078, 0.076, 0.072, 0.92 }
local ICON_BACK = { 0, 0, 0, 0.7 }
local STRATA = "MEDIUM"

local holder, bar, header, title, applyButton, glow, pulse
local slots = {}
local visible = {}
local layoutMotion = {}
local barFade = {}
local timerTicker
local pendingRefresh = false
local readyUntil = 0
local shown = false
local moving = false

local function InCombat()
    return InCombatLockdown()
end

local function RomanRank(rank)
    return ROMAN[rank.index] or tostring(rank.index)
end
Bar.RomanRank = RomanRank

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 60 then
        return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
    end
    return tostring(seconds)
end
Bar.FormatTime = FormatTime

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

local function AddLine(text, color)
    GameTooltip:AddLine(text, color[1], color[2], color[3], true)
end

local function AddStatusLines(record)
    local state = record.state
    if state == Status.MISSING then
        AddLine(L.TIP_MISSING, C.text)
    elseif state == Status.EXPIRING then
        AddLine(string.format(L.TIP_EXPIRING, FormatTime(record.expiration - GetTime())), C.warn)
        if not record.rank then AddLine(L.TIP_NO_REFRESH, C.muted) end
    elseif state == Status.UPGRADE then
        AddLine(string.format(L.TIP_UPGRADE, RomanRank(record.activeRank), RomanRank(record.rank)), C.good)
    elseif state == Status.SELF then
        AddLine(L.TIP_SELF, C.good)
    elseif state == Status.GROUP then
        local provider = record.provider
        local r, g, b = UI.ClassColor(provider.class)
        AddLine(string.format(L.TIP_GROUP, CreateColor(r, g, b):WrapTextInColorCode(provider.name or "?")), C.text)
        AddLine(L.TIP_GROUP_HINT, C.muted)
    elseif state == Status.EMPTY then
        AddLine(L.TIP_EMPTY, C.bad)
    end
end

local countedRanks, lowerRanks, offeredRanks = {}, {}, {}

local function RankBreakdown(family, grade)
    wipe(countedRanks)
    wipe(lowerRanks)
    for _, rank in ipairs(Inventory.OfferRanks(family, UnitLevel("player"), offeredRanks)) do
        local count = Inventory.Count(rank.item)
        if count > 0 then
            local list = grade and rank.index >= grade.index and countedRanks or lowerRanks
            list[#list + 1] = string.format(L.RANK_COUNT, RomanRank(rank), count)
        end
    end
    local counted = #countedRanks > 1 and table.concat(countedRanks, ", ") or nil
    local lower = #lowerRanks > 0 and table.concat(lowerRanks, ", ") or nil
    return counted, lower
end

local function AddStockLines(record)
    if record.spell then return end
    local family = record.family
    local grade = Inventory.StockRank(family)
    local count, bank = Inventory.StockCount(family, grade)
    AddLine(string.format(L.TIP_STOCK, count, Inventory.StockTarget(family)), C.muted)
    if grade and grade ~= Inventory.TopUsableRank(family, UnitLevel("player")) then
        AddLine(string.format(L.TIP_STOCK_FROM, RomanRank(grade)), C.muted)
    end
    local counted, lower = RankBreakdown(family, grade)
    if counted then AddLine(string.format(L.TIP_BY_RANK, counted), C.muted) end
    if lower then AddLine(string.format(L.TIP_LOWER_RANKS, lower), C.muted) end
    if bank > 0 then AddLine(string.format(L.TIP_IN_BANK, bank), C.muted) end
    if record.rank and record.rank ~= record.top then
        AddLine(string.format(L.TIP_LOWER_RANK, RomanRank(record.rank), RomanRank(record.top)), C.warn)
    end
end

local function ShowRecordTooltip(owner, record, hint)
    GameTooltip:SetOwner(owner, UI.VerticalAnchor(owner))
    if record.spell then
        GameTooltip:SetSpellByID(record.spell)
    else
        GameTooltip:SetItemByID((record.rank or record.top).item)
    end
    GameTooltip:AddLine(" ")
    AddStatusLines(record)
    AddStockLines(record)
    if hint then AddLine(L[hint], C.muted) end
    GameTooltip:Show()
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
    if duration > 0 then
        slot.cooldown:SetCooldown(start, duration)
    else
        slot.cooldown:Clear()
    end
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

local function CountColor(record, stock)
    if stock == 0 then return C.bad end
    if stock < Inventory.StockTarget(record.family) then return C.warn end
    return C.text
end

local function SlotCount(record, rank)
    local stock = Inventory.StockCount(record.family)
    if stock > 0 then return stock, stock end
    return Inventory.Count(rank.item), stock
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

    local count, stock
    if not record.spell then count, stock = SlotCount(record, rank) end
    slot.count:SetShown(count ~= nil and ns.db.showCounts)
    if count then
        slot.count:SetText(count)
        slot.count:SetTextColor(unpack(CountColor(record, stock)))
    end

    slot.scrim:SetShown(slot.rankText:IsShown() or slot.count:IsShown())

    local provider = state == Status.GROUP and record.provider or nil
    slot.dot:SetShown(provider ~= nil)
    if provider then slot.dot:SetVertexColor(UI.ClassColor(provider.class)) end

    PaintTimer(slot)
    PaintCooldown(slot)
end

local function Highlight(slot, on)
    UI.Tween(slot.hover, on and HOVER_ALPHA or 0, 0.12, function(_, value) slot.highlight:SetAlpha(value) end)
end

local function SavePosition()
    local point, _, _, x, y = holder:GetPoint(1)
    local position = ns.db.position
    position.point, position.x, position.y = point, x, y
end

local function StartMoving()
    if ns.db.locked or InCombat() then return false end
    moving = true
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
    GameTooltip:Hide()
    return StartMoving()
end

local function SetUpButton(button)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("unit", "player")
    button:SetAttribute("*type2", NO_ACTION)
    button:SetAttribute("alt-type1", NO_ACTION)
    W.DragHandle(button, StartAltMoving, StopMoving)
end

local function OnPreClick(self, button, down)
    if button == "LeftButton" and down and not IsAltKeyDown() then NoteUse(self.record) end
end

local function CreateSlot(index)
    local slot = CreateFrame("Button", "ReScrollSlot" .. index, bar, "SecureActionButtonTemplate")
    SetUpButton(slot)
    slot:Hide()
    slot:SetAlpha(0)

    slot.art = CreateFrame("Frame", nil, slot)
    slot.art:SetAllPoints()
    UI.Fill(slot.art, ICON_BACK)
    slot.icon = slot.art:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", BORDER, -BORDER)
    slot.icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    slot.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    slot.cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot.cooldown:SetAllPoints(slot.icon)
    slot.cooldown:SetDrawEdge(false)
    slot.cooldown:SetHideCountdownNumbers(true)

    local overlay = CreateFrame("Frame", nil, slot)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(slot.cooldown:GetFrameLevel() + 1)
    slot.highlight = UI.Fill(overlay, { 1, 1, 1, 1 }, "ARTWORK")
    slot.highlight:SetPoint("TOPLEFT", BORDER, -BORDER)
    slot.highlight:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    slot.highlight:SetAlpha(0)
    slot.hover = {}

    slot.scrim = overlay:CreateTexture(nil, "BACKGROUND")
    slot.scrim:SetColorTexture(1, 1, 1, 1)
    slot.scrim:SetGradient("VERTICAL", CreateColor(0, 0, 0, SCRIM_ALPHA), CreateColor(0, 0, 0, 0))
    slot.scrim:SetPoint("TOPLEFT", slot, "LEFT", BORDER, 0)
    slot.scrim:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    slot.rankText = UI.BoldText(overlay, T.caption, C.text)
    slot.rankText:SetPoint("BOTTOMLEFT", LABEL_INSET, LABEL_INSET)
    slot.count = UI.BoldText(overlay, T.body, C.text)
    slot.count:SetPoint("BOTTOMRIGHT", -LABEL_INSET, LABEL_INSET - 1)
    slot.timerScrim = overlay:CreateTexture(nil, "BACKGROUND")
    slot.timerScrim:SetColorTexture(1, 1, 1, 1)
    slot.timerScrim:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, SCRIM_ALPHA))
    slot.timerScrim:SetPoint("TOPLEFT", BORDER, -BORDER)
    slot.timerScrim:SetPoint("BOTTOMRIGHT", slot, "RIGHT", -BORDER, 0)
    slot.timerScrim:Hide()
    slot.timer = UI.BoldText(overlay, T.body, C.warn)
    slot.timer:SetPoint("TOP", 0, -LABEL_INSET)
    slot.dot = W.Circle(overlay, "OVERLAY")
    slot.dot:SetSize(DOT_SIZE, DOT_SIZE)
    slot.dot:SetPoint("TOPRIGHT", -3, -3)

    slot.fade = {}
    slot:SetScript("PreClick", OnPreClick)
    slot:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and not down and self.record and not ns.TestMode.active and not InCombat() then
            Status.Snooze(self.record.family)
        end
    end)
    slot:HookScript("OnEnter", function(self)
        Highlight(self, true)
        if self.record then ShowRecordTooltip(self, self.record, "TIP_SNOOZE") end
    end)
    slot:HookScript("OnLeave", function(self)
        Highlight(self, false)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    slot:HookScript("OnMouseDown", function(self)
        self.icon:SetPoint("TOPLEFT", BORDER + PRESS_INSET, -BORDER - PRESS_INSET)
        self.icon:SetPoint("BOTTOMRIGHT", -BORDER - PRESS_INSET, BORDER + PRESS_INSET)
    end)
    slot:HookScript("OnMouseUp", function(self)
        self.icon:SetPoint("TOPLEFT", BORDER, -BORDER)
        self.icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    end)
    slots[index] = slot
    return slot
end

local function PaintApply(chain)
    local upcoming = chain[1]
    applyButton.record = upcoming
    SetAction(applyButton, upcoming)
    applyButton.label:SetText(L.APPLY)
    local width = math.ceil(applyButton.label:GetStringWidth()) + APPLY_TEXT_PAD * 2
    applyButton:SetSize(math.max(APPLY_MIN_WIDTH, width), ns.db.iconSize)
end

local function CreateApplyButton()
    applyButton = CreateFrame("Button", Bar.APPLY_BUTTON, bar, "SecureActionButtonTemplate")
    SetUpButton(applyButton)
    local fill = applyButton:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    W.HoverFill(applyButton, fill, C.accent, { 0.973, 0.792, 0.420, 1 })
    applyButton.label = UI.BoldText(applyButton, T.label, C.onAccent)
    applyButton.label:SetPoint("CENTER")
    applyButton.fade = {}
    applyButton:SetScript("PreClick", OnPreClick)
    applyButton:HookScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 0, -PRESS_INSET) end)
    applyButton:HookScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
end

local function CreateHeader()
    header = CreateFrame("Frame", nil, bar)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:EnableMouse(true)
    local glyph = UI.AddonGlyph(header, HEADER_GLYPH_HEIGHT)
    glyph:SetPoint("LEFT")
    title = UI.BoldText(header, T.label, C.text)
    title:SetPoint("LEFT", glyph, "RIGHT", HEADER_GLYPH_GAP, 0)
    header:SetScript("OnEnter", function(self)
        W.ShowHint(self, ns.db.locked and "HEADER_LOCKED_DESC" or "HEADER_DESC")
    end)
    header:SetScript("OnLeave", W.HideHint)
    header:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ns.Options.Toggle()
        elseif button == "MiddleButton" and not ns.db.locked then
            Bar.ResetPosition()
        end
    end)
    W.DragHandle(header, StartMoving, StopMoving)
end

function Bar.ResetPosition()
    local position, default = ns.db.position, ns.DEFAULTS.position
    position.point, position.x, position.y = default.point, default.x, default.y
    ns.Fire("SETTING_CHANGED", "position")
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

local function Create()
    holder = CreateFrame("Frame", "ReScrollHolder", UIParent)
    holder:SetSize(1, 1)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    holder:SetFrameStrata(STRATA)
    holder:SetToplevel(true)
    RegisterStateDriver(holder, "visibility", "[combat] hide; show")

    bar = CreateFrame("Frame", "ReScrollBar", holder)
    bar:Hide()
    bar:SetAlpha(0)
    UI.Fill(bar, BACKGROUND)
    CreatePulse()
    CreateHeader()
    CreateApplyButton()
    for index = 1, #ns.FAMILIES do
        CreateSlot(index)
    end
end

local function PlaceHolder()
    local position = ns.db.position
    holder:ClearAllPoints()
    holder:SetPoint(position.point, UIParent, position.point, position.x, position.y)
    bar:ClearAllPoints()
    local grow = ns.db.grow
    if grow == "LEFT" then
        bar:SetPoint("TOPRIGHT", holder, "CENTER")
    elseif grow == "CENTER" then
        bar:SetPoint("TOP", holder, "CENTER")
    else
        bar:SetPoint("TOPLEFT", holder, "CENTER")
    end
end

local function RowTop()
    return PAD + (ns.db.showHeader and HEADER_HEIGHT + HEADER_GAP or 0)
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
        if slot.leaving and not InCombat() then
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
    header:SetShown(ns.db.showHeader)
    title:SetText(L.HEADER)
    PaintApply(chain)

    wipe(visible)
    local top, left = RowTop(), PAD
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
            if not shown and not InCombat() then bar:Hide() end
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
    if InCombat() then
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

function Bar.Pulse()
    if pulse then pulse:Play() end
end

ns.Listen("STATUS_CHANGED", RefreshAnimated)
ns.Listen("TEST_MODE_CHANGED", RefreshAnimated)
ns.Listen("OPTIONS_SHOWN", RefreshAnimated)
ns.Listen("LOCALE_CHANGED", function() Bar.Refresh(false) end)
ns.Listen("SETTING_CHANGED", function(key)
    if not holder then return end
    if key == nil or key == "position" or key == "grow" then
        if not InCombat() then PlaceHolder() end
    end
    Bar.Refresh(false)
end)

ns.Listen("LOGIN", function()
    Create()
    PlaceHolder()
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
        StopMoving()
        FinishHiding()
        if pendingRefresh then Bar.Refresh(false) end
    end)
    ns.RegisterEvent("READY_CHECK", OnReadyCheck)
    ns.RegisterEvent("BAG_UPDATE_COOLDOWN", RefreshCooldowns)
    ns.RegisterEvent("SPELL_UPDATE_COOLDOWN", RefreshCooldowns)
    Bar.Refresh(false)
end)
