local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT

local Widgets = {}
ns.Widgets = Widgets

local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local HOVER_TIME = 0.12
local MOVE_TIME = 0.18
local ROW_HEIGHT = 24
local SWITCH_WIDTH, SWITCH_HEIGHT, KNOB_INSET = 26, 14, 2
local BUTTON_HEIGHT, BUTTON_PAD, GROUP_GAP = 22, 10, 2
local THUMB_SIZE, THUMB_HOVER_SIZE, RAIL_HEIGHT = 10, 12, 3
local ROW_HOVER = { 1, 1, 1, 0.035 }
local LOCKED_ALPHA = 0.5
local SCROLLBAR_INSET = 2

local bound = {}
local localeHooks = {}
local afterLocaleHooks = {}
local scratchColor = {}

function Widgets.Bind(fontString, key)
    bound[#bound + 1] = { fontString, key }
    fontString:SetText(L[key])
end

function Widgets.OnLocale(callback)
    localeHooks[#localeHooks + 1] = callback
end

function Widgets.AfterLocale(callback)
    afterLocaleHooks[#afterLocaleHooks + 1] = callback
end

ns.Listen("LOCALE_CHANGED", function()
    for _, entry in ipairs(bound) do
        entry[1]:SetText(L[entry[2]])
    end
    for _, callback in ipairs(localeHooks) do
        callback()
    end
    for _, callback in ipairs(afterLocaleHooks) do
        callback()
    end
end)

function Widgets.Circle(parent, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetColorTexture(1, 1, 1, 1)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return texture
end

function Widgets.HoverFill(frame, texture, base, hover)
    local state = { base = base, hover = hover }
    local function Apply(_, t)
        texture:SetColorTexture(unpack(UI.LerpColor(state.base, state.hover, t, scratchColor)))
    end
    function state.Repaint()
        Apply(state, state.tweenValue or 0)
    end
    UI.SnapTween(state, 0, Apply)
    frame:HookScript("OnEnter", function() UI.Tween(state, 1, HOVER_TIME, Apply) end)
    frame:HookScript("OnLeave", function() UI.Tween(state, 0, HOVER_TIME, Apply) end)
    return state
end

local function RowHover(row)
    local fill = row:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", -6, 0)
    fill:SetPoint("BOTTOMRIGHT", 6, 0)
    Widgets.HoverFill(row, fill, { 1, 1, 1, 0 }, ROW_HOVER)
end
Widgets.RowHover = RowHover

local function ShowHint(owner, key, anchor)
    if not key then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(L[key], 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function HideHint(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end
Widgets.ShowHint = ShowHint
Widgets.HideHint = HideHint

function Widgets.DragHandle(handle, start, stop)
    local dragging = false
    local function Stop()
        if not dragging then return end
        dragging = false
        stop()
    end
    handle:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or start() == false then return end
        dragging = true
        HideHint(self)
    end)
    handle:HookScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then Stop() end
    end)
    handle:HookScript("OnHide", Stop)
end

function Widgets.Heading(parent, width, key)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 22)
    local text = UI.BoldText(frame, T.heading, C.accent)
    text:SetPoint("BOTTOMLEFT", 0, 5)
    Widgets.Bind(text, key)
    return frame
end

function Widgets.Paragraph(parent, width, key, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetWidth(width)
    local text = UI.Text(frame, size or T.label, C.muted)
    text:SetPoint("TOPLEFT")
    text:SetWidth(width)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)
    Widgets.Bind(text, key)
    local function Fit()
        frame:SetHeight(math.floor(text:GetStringHeight() + 4))
    end
    Fit()
    Widgets.OnLocale(Fit)
    frame:SetScript("OnShow", Fit)
    frame.text = text
    return frame
end

local BUTTON_STYLES = {
    default = { fill = C.control, hover = C.controlHover, text = C.text },
    primary = { fill = C.accent, hover = { 0.973, 0.792, 0.420, 1 }, text = C.onAccent },
    danger = { fill = C.control, hover = { 0.333, 0.180, 0.165, 1 }, text = C.bad },
}

function Widgets.Button(parent, key, onClick, style, width)
    local look = BUTTON_STYLES[style or "default"]
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(BUTTON_HEIGHT)
    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    local hover = Widgets.HoverFill(button, fill, look.fill, look.hover)
    button.text = UI.BoldText(button, T.label, look.text)
    button.text:SetPoint("CENTER")
    function button:SetStyle(name)
        local chosen = BUTTON_STYLES[name]
        hover.base, hover.hover = chosen.fill, chosen.hover
        hover.Repaint()
        self.text:SetTextColor(unpack(chosen.text))
    end
    function button:Fit()
        self:SetWidth(width or math.ceil(self.text:GetStringWidth() + BUTTON_PAD * 2))
    end
    if key then Widgets.Bind(button.text, key) end
    button:Fit()
    Widgets.OnLocale(function() button:Fit() end)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnMouseDown", function(self) self.text:SetPoint("CENTER", 0, -1) end)
    button:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)
    return button
end

function Widgets.CreateSwitch(parent)
    local switch = CreateFrame("Frame", nil, parent)
    switch:SetSize(SWITCH_WIDTH, SWITCH_HEIGHT)
    switch.left = Widgets.Circle(switch, "ARTWORK")
    switch.left:SetSize(SWITCH_HEIGHT, SWITCH_HEIGHT)
    switch.left:SetPoint("LEFT")
    switch.right = Widgets.Circle(switch, "ARTWORK")
    switch.right:SetSize(SWITCH_HEIGHT, SWITCH_HEIGHT)
    switch.right:SetPoint("RIGHT")
    switch.middle = switch:CreateTexture(nil, "ARTWORK")
    switch.middle:SetColorTexture(1, 1, 1, 1)
    switch.middle:SetPoint("TOPLEFT", SWITCH_HEIGHT / 2, 0)
    switch.middle:SetPoint("BOTTOMRIGHT", -SWITCH_HEIGHT / 2, 0)
    local knobSize = SWITCH_HEIGHT - KNOB_INSET * 2
    switch.knob = Widgets.Circle(switch, "OVERLAY")
    switch.knob:SetSize(knobSize, knobSize)
    switch.travel = SWITCH_WIDTH - knobSize - KNOB_INSET * 2
    switch.state = {}
    switch.hovered = false
    return switch
end

local OFF_KNOB = { 0.600, 0.584, 0.553, 1 }
local ON_KNOB = { 0.098, 0.074, 0.031, 1 }

local function PaintSwitch(switch, value)
    local offTrack = switch.hovered and C.controlHover or C.control
    local r, g, b, a = unpack(UI.LerpColor(offTrack, C.accent, value, scratchColor))
    switch.left:SetVertexColor(r, g, b, a)
    switch.right:SetVertexColor(r, g, b, a)
    switch.middle:SetVertexColor(r, g, b, a)
    switch.knob:SetVertexColor(unpack(UI.LerpColor(OFF_KNOB, ON_KNOB, value, scratchColor)))
    switch.knob:SetPoint("LEFT", KNOB_INSET + switch.travel * value, 0)
end

function Widgets.SetSwitch(switch, on, animate)
    local target = on and 1 or 0
    local function Apply(_, value) PaintSwitch(switch, value) end
    if animate then
        UI.Tween(switch.state, target, MOVE_TIME, Apply)
    else
        UI.SnapTween(switch.state, target, Apply)
    end
end

function Widgets.SetSwitchHover(switch, hovered)
    switch.hovered = hovered
    PaintSwitch(switch, switch.state.tweenValue or 0)
end

function Widgets.Toggle(parent, width, opts)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, ROW_HEIGHT)
    RowHover(row)
    local switch = Widgets.CreateSwitch(row)
    switch:SetPoint("RIGHT")
    local label = UI.Text(row, T.body, C.text)
    label:SetPoint("LEFT")
    label:SetPoint("RIGHT", switch, "LEFT", -12, 0)
    label:SetJustifyH("LEFT")
    Widgets.Bind(label, opts.label)
    local function IsLocked()
        return opts.locked ~= nil and opts.locked()
    end
    row:SetScript("OnClick", function()
        if IsLocked() then return end
        opts.set(not opts.get())
        Widgets.SetSwitch(switch, opts.get(), true)
    end)
    row:HookScript("OnEnter", function(self)
        local locked = IsLocked()
        Widgets.SetSwitchHover(switch, not locked)
        ShowHint(self, locked and opts.lockedDesc or opts.desc)
    end)
    row:HookScript("OnLeave", function(self)
        Widgets.SetSwitchHover(switch, false)
        HideHint(self)
    end)
    function row:Refresh(animate)
        local locked = IsLocked()
        switch:SetAlpha(locked and LOCKED_ALPHA or 1)
        label:SetTextColor(unpack(locked and C.muted or C.text))
        Widgets.SetSwitch(switch, locked or opts.get(), animate)
    end
    row:Refresh()
    return row
end

local function Snap(value, opts)
    value = math.floor((value - opts.min) / opts.step + 0.5) * opts.step + opts.min
    return math.max(opts.min, math.min(opts.max, value))
end

local function FormatValue(value, opts)
    if opts.format then return opts.format(value) end
    return tostring(math.floor(value + 0.5))
end

function Widgets.Slider(parent, width, opts)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 34)
    local label = UI.Text(row, T.label, C.muted)
    label:SetPoint("TOPLEFT", 0, -2)
    label:SetPoint("RIGHT", -42, 0)
    label:SetJustifyH("LEFT")
    Widgets.Bind(label, opts.label)

    local box = CreateFrame("EditBox", nil, row)
    box:SetSize(40, 18)
    box:SetPoint("TOPRIGHT", 0, 1)
    box:SetAutoFocus(false)
    box:SetJustifyH("RIGHT")
    box:SetTextInsets(3, 3, 0, 0)
    box:SetFontObject(UI.Font(T.body))
    box:SetTextColor(unpack(C.text))
    local boxFill = UI.Fill(box, C.control)
    boxFill:SetAlpha(0)

    local track = CreateFrame("Frame", nil, row)
    track:SetPoint("BOTTOMLEFT", THUMB_HOVER_SIZE / 2, 0)
    track:SetPoint("BOTTOMRIGHT", -THUMB_HOVER_SIZE / 2, 0)
    track:SetHeight(12)
    track:EnableMouse(true)
    local rail = track:CreateTexture(nil, "ARTWORK")
    rail:SetColorTexture(unpack(C.control))
    rail:SetHeight(RAIL_HEIGHT)
    rail:SetPoint("LEFT")
    rail:SetPoint("RIGHT")
    local fill = track:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetColorTexture(unpack(C.accent))
    fill:SetHeight(RAIL_HEIGHT)
    fill:SetPoint("LEFT")
    local thumb = Widgets.Circle(track, "OVERLAY")
    thumb:SetSize(THUMB_SIZE, THUMB_SIZE)
    thumb:SetVertexColor(unpack(C.text))

    local thumbState = {}
    local function SizeThumb(_, value)
        local size = UI.Lerp(THUMB_SIZE, THUMB_HOVER_SIZE, value)
        thumb:SetSize(size, size)
    end

    local function Paint(value)
        local ratio = (value - opts.min) / (opts.max - opts.min)
        local span = track:GetWidth()
        if span <= 0 then span = width - THUMB_HOVER_SIZE end
        fill:SetWidth(math.max(0.001, span * ratio))
        thumb:SetPoint("CENTER", track, "LEFT", span * ratio, 0)
        if not box:HasFocus() then
            box:SetText(FormatValue(value, opts))
        end
    end

    local function Commit(value)
        value = Snap(value, opts)
        if value ~= opts.get() then
            opts.set(value)
        end
        Paint(opts.get())
    end

    local function FromCursor()
        local x = GetCursorPosition() / track:GetEffectiveScale()
        local ratio = (x - track:GetLeft()) / track:GetWidth()
        Commit(opts.min + math.max(0, math.min(1, ratio)) * (opts.max - opts.min))
    end

    track:SetScript("OnMouseDown", function(self)
        FromCursor()
        self:SetScript("OnUpdate", FromCursor)
    end)
    track:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    track:SetScript("OnEnter", function() UI.Tween(thumbState, 1, HOVER_TIME, SizeThumb) end)
    track:SetScript("OnLeave", function() UI.Tween(thumbState, 0, HOVER_TIME, SizeThumb) end)

    box:SetScript("OnEnterPressed", function(self)
        local value = tonumber((self:GetText():gsub("[^%d%.%-]", "")))
        self:ClearFocus()
        if value then Commit(value) else Paint(opts.get()) end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        Paint(opts.get())
    end)
    box:SetScript("OnEditFocusGained", function(self)
        boxFill:SetAlpha(1)
        self:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function()
        boxFill:SetAlpha(0)
        Paint(opts.get())
    end)
    box:SetScript("OnEnter", function() if not box:HasFocus() then boxFill:SetAlpha(0.6) end end)
    box:SetScript("OnLeave", function() if not box:HasFocus() then boxFill:SetAlpha(0) end end)
    track:SetScript("OnSizeChanged", function() Paint(opts.get()) end)

    function row:Refresh()
        Paint(opts.get())
    end
    row:Refresh()
    return row
end

function Widgets.Segmented(parent, width, opts)
    local row = CreateFrame("Frame", nil, parent)
    local top = 0
    if opts.label then
        local label = UI.Text(row, T.label, C.muted)
        label:SetPoint("TOPLEFT", 0, -2)
        Widgets.Bind(label, opts.label)
        top = 18
    end
    row:SetSize(width, top + BUTTON_HEIGHT)

    local bar = CreateFrame("Frame", nil, row)
    bar:SetPoint("TOPLEFT", 0, -top)
    bar:SetSize(width, BUTTON_HEIGHT)
    local selection = bar:CreateTexture(nil, "ARTWORK")
    selection:SetColorTexture(unpack(C.accent))
    selection:SetHeight(BUTTON_HEIGHT)

    local segmentWidth = (width - GROUP_GAP * (opts.count - 1)) / opts.count
    local step = segmentWidth + GROUP_GAP
    local buttons = {}
    local slide = {}

    local function MoveSelection(_, value)
        selection:SetPoint("LEFT", bar, "LEFT", value, 0)
    end

    local function Paint(animate)
        local items = opts.items()
        local current = opts.get()
        local selected = 1
        for index, button in ipairs(buttons) do
            local item = items[index]
            button:SetShown(item ~= nil)
            button.fill:SetShown(item ~= nil)
            if item then
                button.item = item
                button.text:SetText(item.text)
                if item.value == current then selected = index end
            end
        end
        for index, button in ipairs(buttons) do
            button.text:SetTextColor(unpack(index == selected and C.onAccent or C.text))
        end
        selection:SetWidth(segmentWidth)
        local target = (selected - 1) * step
        if animate then
            UI.Tween(slide, target, MOVE_TIME, MoveSelection)
        else
            UI.SnapTween(slide, target, MoveSelection)
        end
    end

    for index = 1, opts.count do
        local button = CreateFrame("Button", nil, bar)
        button:SetSize(segmentWidth, BUTTON_HEIGHT)
        button:SetPoint("LEFT", (index - 1) * step, 0)
        local fill = bar:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(button)
        Widgets.HoverFill(button, fill, C.control, C.controlHover)
        button.fill = fill
        button.text = UI.BoldText(button, T.label, C.text)
        button.text:SetPoint("LEFT", 4, 0)
        button.text:SetPoint("RIGHT", -4, 0)
        button:SetScript("OnClick", function(self)
            opts.set(self.item.value)
            Paint(true)
        end)
        buttons[index] = button
    end

    function row:Refresh(animate)
        Paint(animate)
    end
    Widgets.OnLocale(function() Paint(false) end)
    row:Refresh()
    return row
end

function Widgets.Scroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll.content = content

    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 0.12)
    thumb:SetWidth(2)
    thumb:Hide()

    local motion = {}
    local function Apply(_, value)
        scroll:SetVerticalScroll(value)
        local range = scroll:GetVerticalScrollRange()
        if range <= 0 then
            thumb:Hide()
            return
        end
        local visible = scroll:GetHeight()
        local thumbHeight = math.max(20, visible * visible / (visible + range))
        thumb:SetHeight(thumbHeight)
        thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -SCROLLBAR_INSET, -(visible - thumbHeight) * (value / range))
        thumb:Show()
    end

    function scroll:ScrollTo(value, animate)
        value = math.max(0, math.min(self:GetVerticalScrollRange(), value))
        if animate then
            UI.Tween(motion, value, 0.2, Apply)
        else
            UI.SnapTween(motion, value, Apply)
        end
    end

    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:ScrollTo((motion.tweenValue or 0) - delta * 48, true)
    end)
    scroll:SetScript("OnScrollRangeChanged", function(self)
        self:ScrollTo(motion.tweenValue or 0, false)
    end)
    scroll:SetScript("OnSizeChanged", function(self, w)
        content:SetWidth(w)
        self:ScrollTo(motion.tweenValue or 0, false)
    end)
    return scroll
end

local STACK_BOTTOM_PAD = 12

function Widgets.Stack(content, inset)
    local stack = { content = content, frames = {}, inset = inset or 0 }

    function stack:Reflow()
        local y = 0
        for _, frame in ipairs(self.frames) do
            if frame:IsShown() then
                y = y + frame.stackGap
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", self.inset, -y)
                y = y + frame:GetHeight()
            end
        end
        self.content:SetHeight(y + STACK_BOTTOM_PAD)
    end

    local function Reflow() stack:Reflow() end

    function stack:Add(frame, gap)
        frame.stackGap = gap or 0
        self.frames[#self.frames + 1] = frame
        frame:HookScript("OnSizeChanged", Reflow)
        self:Reflow()
        return frame
    end

    Widgets.AfterLocale(Reflow)
    return stack
end

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true,
}
local MOUSE_KEYS = { LeftButton = true, RightButton = true }
local KEY_BUTTON_WIDTH = 120

local function ComposeKey(key)
    local prefix = ""
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix .. key
end

local function Bind(binding, key)
    local old = GetBindingKey(binding)
    while old do
        SetBinding(old)
        old = GetBindingKey(binding)
    end
    if key then SetBinding(key, binding) end
    SaveBindings(GetCurrentBindingSet())
end

function Widgets.KeyBind(parent, width, opts)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, ROW_HEIGHT)
    local label = UI.Text(row, T.body, C.text)
    label:SetPoint("LEFT")
    Widgets.Bind(label, opts.label)

    local button = CreateFrame("Button", nil, row)
    button:SetSize(KEY_BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetPoint("RIGHT")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    Widgets.HoverFill(button, fill, C.control, C.controlHover)
    local text = UI.BoldText(button, T.label, C.text)
    text:SetPoint("LEFT", 6, 0)
    text:SetPoint("RIGHT", -6, 0)

    local capturing = false
    local function Paint()
        if capturing then
            text:SetText(L.KEY_PRESS)
            text:SetTextColor(unpack(C.accent))
            return
        end
        local key = GetBindingKey(opts.binding)
        text:SetText(key and GetBindingText(key) or L.KEY_NONE)
        text:SetTextColor(unpack(key and C.text or C.muted))
    end

    local function Stop()
        capturing = false
        button:EnableKeyboard(false)
        button:SetScript("OnKeyDown", nil)
        Paint()
    end

    button:SetScript("OnClick", function(self, mouse)
        if InCombatLockdown() then return end
        if mouse == "RightButton" then
            Stop()
            Bind(opts.binding, nil)
            Paint()
            return
        end
        if capturing then
            Stop()
            return
        end
        capturing = true
        self:EnableKeyboard(true)
        self:SetScript("OnKeyDown", function(_, key)
            if MODIFIER_KEYS[key] or MOUSE_KEYS[key] then return end
            if key ~= "ESCAPE" and not InCombatLockdown() then Bind(opts.binding, ComposeKey(key)) end
            Stop()
        end)
        Paint()
    end)
    button:SetScript("OnHide", Stop)
    button:HookScript("OnEnter", function(self) ShowHint(self, opts.desc) end)
    button:HookScript("OnLeave", HideHint)

    function row:Refresh()
        Paint()
    end
    Widgets.OnLocale(Paint)
    row:Refresh()
    return row
end
