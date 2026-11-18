local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets

local SidePanel = {}
ns.SidePanel = SidePanel

local WIDTH = 340
local PAD = 14
local DOCK_ORDER = 10
local DOCK_SLOTS = { "auction", "bank" }
local FREE_STRATA = "HIGH"
local HOST_LEVEL_GAP = 10
local HEADER_HEIGHT = 28
local GLYPH_HEIGHT, GLYPH_GAP = 14, 8
local TOGGLE_HEIGHT, TOGGLE_GAP = 24, 8
local LIST_GAP = 14
local HEAD_HEIGHT, ROW_GAP = 40, 16
local ICON_SIZE, ICON_CROP = 32, 0.08
local FOOTER_HEIGHT = 36
local BUTTON_HEIGHT = 22
local BUTTON_WIDTH = 92
local TEXT_GAP = 10
local DISABLED_ALPHA = 0.4
local FADE_TIME = 0.15
local GOLD, SILVER = 10000, 100
local HAIRLINE = { 1, 1, 1, 0.07 }
local COINS = {
    { size = GOLD, key = "COIN_GOLD", color = "|cffe8c15a" },
    { size = SILVER, key = "COIN_SILVER", color = "|cffc4c9cf" },
    { size = 1, key = "COIN_COPPER", color = "|cffd4895a" },
}

SidePanel.ROW_WIDTH = WIDTH - PAD * 2
SidePanel.TEXT_INDENT = ICON_SIZE + 10
SidePanel.HEAD_HEIGHT = HEAD_HEIGHT
SidePanel.DISABLED_ALPHA = DISABLED_ALPHA
SidePanel.HAIRLINE = HAIRLINE

local function Coin(amount, coin)
    return amount .. coin.color .. L[coin.key] .. "|r"
end

local parts = {}
function SidePanel.Money(copper)
    copper = math.max(0, math.ceil(copper))
    wipe(parts)
    for _, coin in ipairs(COINS) do
        local amount = math.floor(copper / coin.size)
        copper = copper - amount * coin.size
        if amount > 0 then parts[#parts + 1] = Coin(amount, coin) end
    end
    if #parts == 0 then return Coin(0, COINS[#COINS]) end
    return table.concat(parts, " ")
end

function SidePanel.ShortMoney(copper)
    copper = math.max(0, math.ceil(copper))
    if copper >= GOLD * 10 then return Coin(math.floor(copper / GOLD + 0.5), COINS[1]) end
    if copper >= GOLD then
        local gold = string.format("%.1f", copper / GOLD):gsub("%.0$", "")
        return Coin(gold, COINS[1])
    end
    if copper >= SILVER then return Coin(math.floor(copper / SILVER + 0.5), COINS[2]) end
    return Coin(copper, COINS[3])
end

function SidePanel.SetEnabled(button, enabled)
    button:SetEnabled(enabled)
    button:SetAlpha(enabled and 1 or DISABLED_ALPHA)
end

local function Hairline(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(HAIRLINE))
    line:SetHeight(1)
    return line
end

local function CreateGrip(panel, glyph, title)
    local grip = CreateFrame("Frame", nil, panel)
    grip:SetPoint("LEFT", glyph, "LEFT")
    grip:SetPoint("RIGHT", title, "RIGHT")
    grip:SetHeight(HEADER_HEIGHT)
    grip:EnableMouse(true)
    grip:SetScript("OnMouseUp", function(_, button) panel:GetScript("OnMouseUp")(panel, button) end)
    W.DragHandle(grip, function() panel:BeginDrag() end, function() panel:EndDrag() end)
    grip:SetScript("OnEnter", function(self) W.ShowHint(self, "HEADER_DESC") end)
    grip:SetScript("OnLeave", W.HideHint)
end

local function CreateHeader(panel, opts)
    local glyph = UI.AddonGlyph(panel, GLYPH_HEIGHT)
    glyph:SetPoint("TOPLEFT", PAD, -PAD - 3)
    local title = UI.BoldText(panel, T.title, C.text)
    title:SetPoint("LEFT", glyph, "RIGHT", GLYPH_GAP, 0)
    W.Bind(title, opts.title)
    CreateGrip(panel, glyph, title)

    local close = CreateFrame("Button", nil, panel)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 2)
    local cross = UI.Text(close, 18, C.muted)
    cross:SetPoint("CENTER", 0, 1)
    cross:SetText("×")
    close:SetScript("OnClick", function() panel:Hide() end)
    close:SetScript("OnEnter", function() cross:SetTextColor(unpack(C.text)) end)
    close:SetScript("OnLeave", function() cross:SetTextColor(unpack(C.muted)) end)

    if opts.refresh then
        local refresh = W.Button(panel, "AH_REFRESH", opts.refresh)
        refresh:SetPoint("RIGHT", close, "LEFT", -6, 0)
    end

    panel.subtitle = UI.Text(panel, T.label, C.muted)
    panel.subtitle:SetPoint("TOPLEFT", PAD, -PAD - HEADER_HEIGHT)
    panel.subtitle:SetWidth(SidePanel.ROW_WIDTH)
    panel.subtitle:SetWordWrap(true)
    panel.subtitle:SetJustifyH("LEFT")
end

local function CreateToggle(panel, toggle)
    local key = toggle.key
    panel.toggle = W.Toggle(panel, SidePanel.ROW_WIDTH, {
        label = toggle.label,
        desc = toggle.desc,
        get = function() return ns.db[key] end,
        set = function(value) ns.Set(key, value) end,
    })
    panel.toggle:SetPoint("TOPLEFT", panel.subtitle, "BOTTOMLEFT", 0, -TOGGLE_GAP)
    ns.Listen("SETTING_CHANGED", function(changed)
        if changed == nil or changed == key then panel.toggle:Refresh(panel:IsShown()) end
    end)
end

local function CreateFooter(panel, opts)
    local line = Hairline(panel)
    line:SetPoint("BOTTOMLEFT", PAD, PAD + FOOTER_HEIGHT)
    line:SetPoint("BOTTOMRIGHT", -PAD, PAD + FOOTER_HEIGHT)
    if opts.onAction then
        panel.action = W.Button(panel, nil, opts.onAction, "primary")
        panel.action:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        panel.action:HookScript("OnEnter", function(self) W.ShowHint(self, opts.actionHint) end)
        panel.action:HookScript("OnLeave", W.HideHint)
    end
    panel.footerText = UI.Text(panel, T.body, C.text)
    panel.footerText:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD, PAD + BUTTON_HEIGHT / 2)
end

local function CreateList(panel, opts)
    panel.list = CreateFrame("Frame", nil, panel)
    panel.list:SetWidth(SidePanel.ROW_WIDTH)
    panel.emptyText = UI.Text(panel.list, T.body, C.muted)
    panel.emptyText:SetPoint("TOPLEFT")
    panel.emptyText:SetWidth(SidePanel.ROW_WIDTH)
    panel.emptyText:SetWordWrap(true)
    panel.emptyText:SetJustifyH("LEFT")
    panel.emptyText:SetSpacing(3)
    W.Bind(panel.emptyText, opts.empty)
end

local function FadeInRow(row)
    row.fade.tweenValue = 0
    row:SetAlpha(0)
    UI.Tween(row.fade, 1, FADE_TIME, function(_, value) row:SetAlpha(value) end)
end

local PanelMixin = {}

function PanelMixin:Offset()
    local offset = self.offset
    return ns.db[offset.x], ns.db[offset.y]
end

function PanelMixin:Dock()
    ns.Dock:Layout()
end

function PanelMixin:Layer()
    local host = ns.Dock:Host(self)
    if not host then
        self:SetFrameStrata(FREE_STRATA)
        return
    end
    self:SetFrameStrata(host:GetFrameStrata())
    self:SetFrameLevel(host:GetFrameLevel() + HOST_LEVEL_GAP)
end

function PanelMixin:Open()
    if self.toggle then self.toggle:Refresh(false) end
    self:Layer()
    UI.FadeIn(self, FADE_TIME)
    self:Dock()
end

function PanelMixin:ListTop()
    local top = PAD + HEADER_HEIGHT + math.ceil(self.subtitle:GetStringHeight())
    if self.toggle then top = top + TOGGLE_GAP + TOGGLE_HEIGHT end
    return top + LIST_GAP
end

function PanelMixin:PaintRows(entries, create, paint)
    local rows, y = self.rows, 0
    for index, entry in ipairs(entries) do
        local row = rows[index]
        if not row then
            row = create(self)
            rows[index] = row
        end
        local fresh = row.entry ~= entry
        row.entry = entry
        paint(row, fresh)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row.divider:SetShown(index > 1)
        y = y + row:GetHeight() + ROW_GAP
        if fresh then FadeInRow(row) end
        row:Show()
    end
    for index = #entries + 1, #rows do
        rows[index].entry = nil
        rows[index]:Hide()
    end

    local count = #entries
    self.emptyText:SetShown(count == 0)
    local listHeight = count > 0 and y - ROW_GAP or math.ceil(self.emptyText:GetStringHeight())
    local top = self:ListTop()
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", PAD, -top)
    self.list:SetHeight(listHeight)
    if self.action then self.action:SetShown(count > 0) end
    self:SetHeight(top + listHeight + LIST_GAP + FOOTER_HEIGHT + PAD)
end

function PanelMixin:SetAction(text, enabled)
    self.action.text:SetText(text)
    self.action:Fit()
    SidePanel.SetEnabled(self.action, enabled)
end

local function Round(value)
    return math.floor(value + 0.5)
end

function PanelMixin:BeginDrag()
    self.dragLeft, self.dragTop = self:GetLeft(), self:GetTop()
    self:StartMoving()
end

function PanelMixin:EndDrag()
    self:StopMovingOrSizing()
    local x, y = self:Offset()
    if self.dragLeft and self.dragTop then
        ns.Set(self.offset.x, x + Round(self:GetLeft() - self.dragLeft))
        ns.Set(self.offset.y, y + Round(self:GetTop() - self.dragTop))
    end
    self.dragLeft, self.dragTop = nil, nil
    self:Dock()
end

local function MakeMovable(panel, opts)
    local offset = opts.offset
    panel.offset = offset
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    ns.Dock:Register(panel, {
        addon = ns.ADDON,
        slot = opts.slot,
        hosts = opts.hosts,
        offset = function() return panel:Offset() end,
    })
    ns.Listen("SETTING_CHANGED", function(key)
        if panel:IsShown() and (key == nil or key == offset.x or key == offset.y) then panel:Dock() end
    end)
end

function SidePanel.Create(name, opts)
    local panel = CreateFrame("Frame", name, UIParent)
    Mixin(panel, PanelMixin)
    panel:SetWidth(WIDTH)
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:Hide()
    panel.rows = {}
    UI.Fill(panel, C.window)
    CreateHeader(panel, opts)
    if opts.toggle then CreateToggle(panel, opts.toggle) end
    CreateList(panel, opts)
    CreateFooter(panel, opts)
    MakeMovable(panel, opts)
    panel:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ns.Options.Toggle(opts.settingsPage)
        elseif button == "MiddleButton" then
            ns.Set(opts.offset.x, 0)
            ns.Set(opts.offset.y, 0)
        end
    end)
    W.DragHandle(panel, function() panel:BeginDrag() end, function() panel:EndDrag() end)
    return panel
end

function SidePanel.Placement(slot)
    return ns.db.dock[slot]
end

function SidePanel.SetPlacement(slot, target, side)
    if target == nil then
        ns.db.dock[slot] = nil
    else
        ns.db.dock[slot] = { target = target, side = side, at = time() }
    end
    ns.Dock:Changed()
end

ns.Listen("DB_READY", function()
    ns.Dock:Join(ns.ADDON, { order = DOCK_ORDER, slots = DOCK_SLOTS, placement = SidePanel.Placement })
end)

ns.Listen("SETTING_CHANGED", function(key)
    if key == nil then ns.Dock:Changed() end
end)

local function ShowRowTooltip(head)
    local row = head:GetParent()
    GameTooltip:SetOwner(head, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.tooltipItem(row.entry))
    GameTooltip:Show()
end

function SidePanel.NewRow(panel, onButton, tooltipItem)
    local row = CreateFrame("Frame", nil, panel.list)
    row:SetSize(SidePanel.ROW_WIDTH, HEAD_HEIGHT)
    row.tooltipItem = tooltipItem
    row.fade = {}

    row.divider = Hairline(row)
    row.divider:SetPoint("TOPLEFT", 0, ROW_GAP / 2)
    row.divider:SetPoint("TOPRIGHT", 0, ROW_GAP / 2)

    local head = CreateFrame("Frame", nil, row)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEAD_HEIGHT)
    head:EnableMouse(true)

    local back = head:CreateTexture(nil, "ARTWORK")
    back:SetColorTexture(0, 0, 0, 0.7)
    back:SetSize(ICON_SIZE, ICON_SIZE)
    back:SetPoint("LEFT")
    row.icon = head:CreateTexture(nil, "OVERLAY")
    row.icon:SetPoint("TOPLEFT", back, 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", back, -1, 1)
    row.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    row.button = W.Button(head, nil, function() onButton(row.entry) end, "default", BUTTON_WIDTH)
    row.button:SetPoint("RIGHT")
    row.price = UI.Text(head, T.body, C.text)
    row.price:SetPoint("TOPRIGHT", -(BUTTON_WIDTH + TEXT_GAP), -(HEAD_HEIGHT - ICON_SIZE) / 2)
    row.price:SetJustifyH("RIGHT")

    row.name = UI.BoldText(head, T.body, C.text)
    row.name:SetPoint("TOPLEFT", back, "TOPRIGHT", 10, 0)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.detail = UI.Text(head, T.label, C.muted)
    row.detail:SetPoint("BOTTOMLEFT", back, "BOTTOMRIGHT", 10, 0)
    row.detail:SetPoint("RIGHT", row.button, "LEFT", -TEXT_GAP, 0)
    row.detail:SetJustifyH("LEFT")

    head:SetScript("OnEnter", ShowRowTooltip)
    head:SetScript("OnLeave", W.HideHint)
    W.RowHover(head)
    return row
end

function SidePanel.ScrollName(family, rank)
    local name = ns.Catalog.Name(family)
    if #family.ranks > 1 then name = name .. " " .. ns.Bar.RomanRank(rank) end
    return name
end
