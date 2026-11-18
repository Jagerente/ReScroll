local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Catalog = ns.Catalog
local Inventory = ns.Inventory

local Options = {}
ns.Options = Options

local WIDTH, HEIGHT = 380, 560
local MARGIN = 14
local HEADER_HEIGHT, TABS_HEIGHT, BODY_GAP = 38, 26, 10
local HEADER_GLYPH_HEIGHT, HEADER_GLYPH_GAP = 16, 8
local SETTINGS_GLYPH_HEIGHT = 20
local TAB_PAD, MIN_TAB_PAD, TAB_GAP = 8, 4, 4
local PAGE_WIDTH = WIDTH - MARGIN * 2
local CONTENT_INSET = 8
local SECTION_GAP = 10
local SLIDER_GAP = 8
local PARAGRAPH_GAP = 4
local FAMILY_ROW_HEIGHT = 28
local FAMILY_ICON_SIZE = 20
local ICON_CROP = 0.08
local DRAG_ALPHA = 0.45
local DROP_LINE_HEIGHT = 2
local RESET_CONFIRM_SECONDS = 3
local PANEL_OFFSET = 500

local window
local pages = {}
local tabButtons = {}
local tabPad = TAB_PAD
local currentPage
local previewStartedHere = false

local function Setting(key)
    return function() return ns.db[key] end, function(value) ns.Set(key, value) end
end

local function Track(page, widget)
    page.widgets[#page.widgets + 1] = widget
    return widget
end

local function AddToggle(page, key, label, desc)
    local get, set = Setting(key)
    return page.stack:Add(Track(page, W.Toggle(page.content, PAGE_WIDTH, { label = label, desc = desc, get = get, set = set })))
end

local function AddSlider(page, key, label, min, max, format, gap)
    local get, set = Setting(key)
    return page.stack:Add(Track(page, W.Slider(page.content, PAGE_WIDTH, {
        label = label, min = min, max = max, step = 1, get = get, set = set, format = format,
    })), gap or SLIDER_GAP)
end

local function AddSegmented(page, key, label, items, gap)
    local get, set = Setting(key)
    return page.stack:Add(Track(page, W.Segmented(page.content, PAGE_WIDTH, {
        label = label, count = #items, get = get, set = set,
        items = function()
            local list = {}
            for i, item in ipairs(items) do
                list[i] = { value = item.value, text = L[item.key] }
            end
            return list
        end,
    })), gap)
end

local function AddHeading(page, key)
    return page.stack:Add(W.Heading(page.content, PAGE_WIDTH, key), #page.stack.frames > 0 and SECTION_GAP or 0)
end

local function AddParagraph(page, key, gap)
    return page.stack:Add(W.Paragraph(page.content, PAGE_WIDTH, key), gap or PARAGRAPH_GAP)
end

local function AddLiveText(page, build, color, gap)
    local frame = CreateFrame("Frame", nil, page.content)
    frame:SetWidth(PAGE_WIDTH)
    local text = UI.Text(frame, T.label, color)
    text:SetPoint("TOPLEFT")
    text:SetWidth(PAGE_WIDTH)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)
    function frame:Refresh()
        text:SetText(build())
        self:SetHeight(math.floor(text:GetStringHeight() + 4))
    end
    frame:Refresh()
    page.stack:Add(Track(page, frame), gap)
    return frame
end

local function NewPage(id)
    local scroll = W.Scroll(window.body)
    scroll:SetAllPoints(window.body)
    scroll:Hide()
    local page = { id = id, scroll = scroll, content = scroll.content, widgets = {} }
    page.stack = W.Stack(page.content, CONTENT_INSET)
    pages[id] = page
    return page
end

local function RefreshPage(page, animate)
    for _, widget in ipairs(page.widgets) do
        widget:Refresh(animate)
    end
    if page.OnShow then page:OnShow() end
end

local function IsCurrent(page)
    return window and window:IsShown() and currentPage == page
end

local function FamilySummary(family)
    if Inventory.TopUsableRank(family, UnitLevel("player")) then return "" end
    return string.format(L.FROM_LEVEL, family.ranks[1].level)
end

local function CreateFamilyRow(parent, list)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(PAGE_WIDTH, FAMILY_ROW_HEIGHT)
    row:RegisterForDrag("LeftButton")
    W.RowHover(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(FAMILY_ICON_SIZE, FAMILY_ICON_SIZE)
    row.icon:SetPoint("LEFT")
    row.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    row.switch = W.CreateSwitch(row)
    row.switch:SetPoint("RIGHT")
    row.status = UI.Text(row, T.label, C.muted)
    row.status:SetPoint("RIGHT", row.switch, "LEFT", -12, 0)
    row.status:SetJustifyH("RIGHT")
    row.name = UI.Text(row, T.body, C.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")

    function row:Paint(animate)
        local family = self.family
        self.icon:SetTexture(Catalog.Icon(family))
        self.name:SetText(Catalog.Name(family))
        self.status:SetText(FamilySummary(family))
        W.SetSwitch(self.switch, Catalog.IsEnabled(family), animate)
    end

    row:SetScript("OnMouseDown", function(self) self.dragged = false end)
    row:SetScript("OnClick", function(self)
        if self.dragged then return end
        Catalog.SetEnabled(self.family, not Catalog.IsEnabled(self.family))
        self:Paint(true)
    end)
    row:HookScript("OnEnter", function(self)
        W.SetSwitchHover(self.switch, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.family.top.item)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.FAMILY_ROW_DESC, unpack(C.muted))
        GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function(self)
        W.SetSwitchHover(self.switch, false)
        W.HideHint(self)
    end)
    row:SetScript("OnDragStart", function(self) list:BeginDrag(self) end)
    row:SetScript("OnDragStop", function(self) list:EndDrag(self) end)
    return row
end

local function CreateFamilyList(page)
    local list = { rows = {} }
    local dropLine = page.content:CreateTexture(nil, "OVERLAY")
    dropLine:SetColorTexture(unpack(C.accent))
    dropLine:SetHeight(DROP_LINE_HEIGHT)
    dropLine:Hide()

    local function CursorY()
        local _, y = GetCursorPosition()
        return y / page.content:GetEffectiveScale()
    end

    local function DropIndex()
        local y = CursorY()
        for index, row in ipairs(list.rows) do
            local top, bottom = row:GetTop(), row:GetBottom()
            if top and bottom and y > (top + bottom) / 2 then return index end
        end
        return #list.rows + 1
    end

    local function PlaceDropLine(index)
        local anchor = list.rows[math.min(index, #list.rows)]
        dropLine:ClearAllPoints()
        local edge = index > #list.rows and "BOTTOM" or "TOP"
        dropLine:SetPoint(edge .. "LEFT", anchor, edge .. "LEFT", 0, 0)
        dropLine:SetPoint(edge .. "RIGHT", anchor, edge .. "RIGHT", 0, 0)
    end

    function list:BeginDrag(row)
        row.dragged = true
        row:SetAlpha(DRAG_ALPHA)
        self.dropIndex = DropIndex()
        PlaceDropLine(self.dropIndex)
        dropLine:Show()
        row:SetScript("OnUpdate", function()
            local index = DropIndex()
            if index ~= self.dropIndex then
                self.dropIndex = index
                PlaceDropLine(index)
            end
        end)
    end

    function list:EndDrag(row)
        row:SetScript("OnUpdate", nil)
        row:SetAlpha(1)
        dropLine:Hide()
        local from
        for index, candidate in ipairs(self.rows) do
            if candidate == row then from = index end
        end
        local to = self.dropIndex or from
        if to > from then to = to - 1 end
        if to ~= from then Catalog.Move(row.family.key, to) end
    end

    function list:Paint(animate)
        for index, family in ipairs(Catalog.ordered) do
            local row = self.rows[index]
            row.family = family
            row:Paint(animate)
        end
    end

    for index = 1, #Catalog.ordered do
        list.rows[index] = page.stack:Add(CreateFamilyRow(page.content, list), index == 1 and 2 or 0)
    end
    return list
end

local function AddLearnedButton(page)
    local button = W.Button(page.content, nil, function()
        ns.Learning.Forget()
    end)
    local function Paint()
        local count = ns.Learning.Count()
        button.text:SetText(string.format(L.FORGET_LEARNED, count))
        button:Fit()
        button:SetShown(count > 0)
        page.stack:Reflow()
    end
    button:HookScript("OnEnter", function(self) W.ShowHint(self, "FORGET_LEARNED_DESC") end)
    button:HookScript("OnLeave", W.HideHint)
    page.stack:Add(button, 12)
    ns.Listen("LEARNED", Paint)
    W.OnLocale(Paint)
    Paint()
    return button
end

local function FormatPercent(value)
    return string.format("%d%%", value)
end

local function BuildScrolls()
    local page = NewPage("scrolls")
    AddHeading(page, "SECTION_FAMILIES")
    AddParagraph(page, "FAMILIES_EXPLAIN", 0)
    local list = CreateFamilyList(page)

    AddHeading(page, "SECTION_RULES")
    AddToggle(page, "groupBuffs", "GROUP_BUFFS", "GROUP_BUFFS_DESC")
    AddToggle(page, "lowerRanks", "LOWER_RANKS", "LOWER_RANKS_DESC")
    AddToggle(page, "upgrades", "UPGRADES", "UPGRADES_DESC")
    AddToggle(page, "showEmpty", "SHOW_EMPTY", "SHOW_EMPTY_DESC")
    AddSlider(page, "expireMinutes", "EXPIRE_MINUTES", 0, 15, nil, 10)
    AddSlider(page, "stock", "STOCK", 0, 20)
    AddLearnedButton(page)

    function page:OnShow()
        list:Paint(false)
    end
    local function RepaintIfVisible()
        if IsCurrent(page) then list:Paint(true) end
    end
    ns.Listen("FAMILIES_CHANGED", RepaintIfVisible)
    ns.Listen("STATUS_CHANGED", RepaintIfVisible)
end

local AUTO = "auto"
local DOCK_SIDE_GAP, DOCK_TEXT_GAP = 10, 8
local DOCK_PAGES = { "auction", "bank" }

local function DockPlacement(slot)
    return ns.SidePanel.Placement(slot)
end

local function DockTargets(slot)
    local items = {
        { value = AUTO, text = L.DOCK_AUTO },
        { value = ns.Dock.HOST, text = L["DOCK_HOST_" .. slot] },
    }
    for _, name in ipairs(ns.Dock:Family(slot)) do
        if name ~= ns.ADDON and ns.Dock:CanAttach(ns.ADDON, slot, name) then
            items[#items + 1] = { value = name, text = name }
        end
    end
    return items
end

local function DefaultSide(target)
    return target == ns.Dock.HOST and "RIGHT" or "BELOW"
end

local function SetDockTarget(slot, target)
    if target == AUTO then
        ns.SidePanel.SetPlacement(slot, nil)
        return
    end
    local placement = DockPlacement(slot)
    ns.SidePanel.SetPlacement(slot, target, placement and placement.side or DefaultSide(target))
end

local function SetDockSide(slot, side)
    local placement = DockPlacement(slot)
    if placement then ns.SidePanel.SetPlacement(slot, placement.target, side) end
end

local function DockStatus(slot)
    local parent, side, takenBy = ns.Dock:Place(ns.ADDON, slot)
    if not parent then return "" end
    local where = parent == ns.Dock.HOST and L["DOCK_OF_" .. slot] or parent
    local text = string.format(L["DOCK_NOW_" .. side], where)
    if takenBy then text = text .. "\n" .. string.format(L.DOCK_TAKEN, takenBy) end
    return text
end

local function DockFamily(slot)
    return string.format(L.DOCK_EXPLAIN, table.concat(ns.Dock:Family(slot), ", "))
end

local function DockSides()
    local list = {}
    for index, side in ipairs(ns.Dock.SIDES) do
        list[index] = { value = side, text = L["DOCK_SIDE_" .. side] }
    end
    return list
end

local function AddDockControls(page, slot)
    page.stack:Add(Track(page, W.Choices(page.content, PAGE_WIDTH, {
        label = "DOCK_TARGET",
        items = function() return DockTargets(slot) end,
        get = function()
            local placement = DockPlacement(slot)
            return placement and placement.target or AUTO
        end,
        set = function(target) SetDockTarget(slot, target) end,
    })))
    local sides = page.stack:Add(Track(page, W.Segmented(page.content, PAGE_WIDTH, {
        label = "DOCK_SIDE",
        count = #ns.Dock.SIDES,
        items = DockSides,
        get = function()
            local placement = DockPlacement(slot)
            return placement and placement.side
        end,
        set = function(side) SetDockSide(slot, side) end,
    })), DOCK_SIDE_GAP)
    local status = AddLiveText(page, function() return DockStatus(slot) end, C.text, DOCK_TEXT_GAP)
    local paintStatus = status.Refresh
    function status:Refresh()
        sides:SetShown(DockPlacement(slot) ~= nil)
        paintStatus(self)
    end
    status:Refresh()
    AddLiveText(page, function() return DockFamily(slot) end, C.muted, PARAGRAPH_GAP)
end

ns.Dock:OnChange(function()
    for _, id in ipairs(DOCK_PAGES) do
        local page = pages[id]
        if page and IsCurrent(page) then RefreshPage(page, true) end
    end
end)

local function BuildAuction()
    local page = NewPage("auction")
    AddHeading(page, "SECTION_AUCTION")
    AddToggle(page, "auction", "AUCTION", "AUCTION_DESC")
    AddToggle(page, "countBank", "COUNT_BANK", "COUNT_BANK_DESC")
    AddParagraph(page, "BUY_RANK_EXPLAIN", 6)

    AddHeading(page, "SECTION_PRICES")
    AddSlider(page, "priceStep", "PRICE_STEP", 0, 100, FormatPercent)
    AddParagraph(page, "PRICE_STEP_EXPLAIN", 6)

    AddHeading(page, "SECTION_PLACEMENT")
    AddDockControls(page, "auction")
    AddSlider(page, "auctionX", "OFFSET_X", -PANEL_OFFSET, PANEL_OFFSET)
    AddSlider(page, "auctionY", "OFFSET_Y", -PANEL_OFFSET, PANEL_OFFSET)
    AddParagraph(page, "AUCTION_OFFSET_EXPLAIN", 6)
end

local function BuildBank()
    local page = NewPage("bank")
    AddHeading(page, "SECTION_BANK")
    AddToggle(page, "bank", "BANK", "BANK_DESC")
    AddToggle(page, "bankAuto", "BANK_AUTO", "BANK_AUTO_DESC")

    AddHeading(page, "SECTION_PLACEMENT")
    AddDockControls(page, "bank")
    AddSlider(page, "bankX", "OFFSET_X", -PANEL_OFFSET, PANEL_OFFSET)
    AddSlider(page, "bankY", "OFFSET_Y", -PANEL_OFFSET, PANEL_OFFSET)
    AddParagraph(page, "BANK_OFFSET_EXPLAIN", 6)
end

local VISIBILITY_MODES = {
    { value = "always", key = "VISIBILITY_always" },
    { value = "group", key = "VISIBILITY_group" },
    { value = "readycheck", key = "VISIBILITY_readycheck" },
}

local GROW_MODES = {
    { value = "RIGHT", key = "GROW_RIGHT" },
    { value = "CENTER", key = "GROW_CENTER" },
    { value = "LEFT", key = "GROW_LEFT" },
}

local function AddReadyCheckToggle(page)
    local get, set = Setting("readyCheck")
    return page.stack:Add(Track(page, W.Toggle(page.content, PAGE_WIDTH, {
        label = "READY_CHECK", desc = "READY_CHECK_DESC", get = get, set = set,
        locked = function() return ns.db.visibility == "readycheck" end, lockedDesc = "READY_CHECK_LOCKED_DESC",
    })))
end

local function AddRecenterButton(page)
    local button = W.Button(page.content, "RECENTER", function() ns.Bar.ResetPosition() end)
    page.stack:Add(button, 12)
end

local function BuildPanel()
    local page = NewPage("panel")
    AddHeading(page, "SECTION_WHEN")
    AddSegmented(page, "visibility", "VISIBILITY", VISIBILITY_MODES)
    AddParagraph(page, "VISIBILITY_EXPLAIN", 6)
    AddReadyCheckToggle(page)
    AddToggle(page, "hideResting", "HIDE_RESTING", "HIDE_RESTING_DESC")

    AddHeading(page, "SECTION_LOOK")
    AddSlider(page, "iconSize", "ICON_SIZE", 24, 56, nil, 4)
    AddSlider(page, "perRow", "PER_ROW", 1, #ns.FAMILIES)
    AddSlider(page, "spacing", "SPACING", 0, 12)
    AddSegmented(page, "grow", "GROW", GROW_MODES, SLIDER_GAP)
    AddToggle(page, "showHeader", "SHOW_HEADER", "SHOW_HEADER_DESC")
    AddToggle(page, "showCounts", "SHOW_COUNTS", "SHOW_COUNTS_DESC")
    AddToggle(page, "locked", "LOCKED", "LOCKED_DESC")
    AddParagraph(page, "MOVE_EXPLAIN", 6)
    AddRecenterButton(page)
end

local function AddResetButton(page)
    local button
    local function Disarm()
        button.armed = false
        button.text:SetText(L.RESET)
        button:Fit()
    end
    button = W.Button(page.content, "RESET", function(self)
        if self.armed then
            Disarm()
            ns.ResetSettings()
            return
        end
        self.armed = true
        self.text:SetText(L.RESET_CONFIRM)
        self:Fit()
        C_Timer.After(RESET_CONFIRM_SECONDS, function()
            if self.armed then Disarm() end
        end)
    end, "danger")
    page.stack:Add(button, 16)
end

local LANGUAGE_ITEMS = {}
for i, code in ipairs(ns.LANGUAGES) do
    LANGUAGE_ITEMS[i] = { value = code, key = "LANGUAGE_" .. code }
end

local function BuildGeneral()
    local page = NewPage("general")
    AddHeading(page, "SECTION_BEHAVIOR")
    AddToggle(page, "enabled", "ENABLE", "ENABLE_DESC")
    page.stack:Add(Track(page, W.KeyBind(page.content, PAGE_WIDTH, {
        label = "APPLY_KEY", desc = "APPLY_KEY_DESC", binding = ns.Bar.BINDING,
    })))
    page.stack:Add(Track(page, W.Toggle(page.content, PAGE_WIDTH, {
        label = "MINIMAP_BUTTON", desc = "MINIMAP_BUTTON_DESC",
        get = function() return not ns.db.minimap.hide end,
        set = ns.MinimapButton.SetShown,
    })))
    AddSegmented(page, "locale", "LANGUAGE", LANGUAGE_ITEMS, SECTION_GAP)
    AddResetButton(page)
end

local function BuildAbout()
    ns.About.Build(NewPage("about"), PAGE_WIDTH)
end

local DEFAULT_PAGE = "scrolls"
local TABS = {
    { id = "scrolls", key = "NAV_SCROLLS", build = BuildScrolls },
    { id = "panel", key = "NAV_PANEL", build = BuildPanel },
    { id = "auction", key = "NAV_AUCTION", build = BuildAuction },
    { id = "bank", key = "NAV_BANK", build = BuildBank },
    { id = "general", key = "NAV_GENERAL", build = BuildGeneral },
    { id = "about", key = "NAV_ABOUT", build = BuildAbout },
}

local function FindTab(id)
    for _, entry in ipairs(TABS) do
        if entry.id == id then return entry end
    end
end

local underline = { x = 0, width = 0, motion = {} }

local function SetUnderline(x, width)
    underline.x, underline.width = x, width
    window.tabUnderline:SetPoint("BOTTOMLEFT", window.tabBar, "BOTTOMLEFT", x, 0)
    window.tabUnderline:SetWidth(math.max(1, width))
end

local function MoveUnderline(button, animate)
    local toX, toWidth = button.offset + tabPad, button:GetWidth() - tabPad * 2
    if not animate then
        UI.SnapTween(underline.motion, 1, function() SetUnderline(toX, toWidth) end)
        return
    end
    local fromX, fromWidth = underline.x, underline.width
    underline.motion.tweenValue = 0
    UI.Tween(underline.motion, 1, 0.2, function(_, t)
        SetUnderline(UI.Lerp(fromX, toX, t), UI.Lerp(fromWidth, toWidth, t))
    end)
end

local function ShowPage(id, animate)
    if not FindTab(id) then id = DEFAULT_PAGE end
    local page = pages[id]
    if not page then
        FindTab(id).build()
        page = pages[id]
    end
    if currentPage and currentPage ~= page then
        currentPage.scroll:Hide()
    end
    currentPage = page
    RefreshPage(page)
    page.scroll:ScrollTo(0, false)
    if animate then
        UI.FadeIn(page.scroll, 0.14)
    else
        page.scroll:Show()
        page.scroll:SetAlpha(1)
    end
    for index, entry in ipairs(TABS) do
        local button = tabButtons[index]
        local selected = entry.id == id
        button.text:SetTextColor(unpack(selected and C.text or C.muted))
        if selected then MoveUnderline(button, animate) end
    end
    ns.db.lastPage = id
end

local function FitTabPad()
    local textWidth = 0
    for _, button in ipairs(tabButtons) do textWidth = textWidth + math.ceil(button.text:GetStringWidth()) end
    local spaces = #tabButtons - 1
    local spare = WIDTH - MARGIN * 2 - textWidth - spaces * TAB_GAP
    return math.max(MIN_TAB_PAD, math.min(TAB_PAD, math.floor(spare / (spaces * 2))))
end

local function LayoutTabs()
    tabPad = FitTabPad()
    local x = -tabPad
    for _, button in ipairs(tabButtons) do
        button:SetWidth(math.ceil(button.text:GetStringWidth()) + tabPad * 2)
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", x, 0)
        button.offset = x
        x = x + button:GetWidth() + TAB_GAP
    end
    if currentPage then
        for index, entry in ipairs(TABS) do
            if entry.id == currentPage.id then MoveUnderline(tabButtons[index], false) end
        end
    end
end

local function CreateTabs()
    local bar = CreateFrame("Frame", nil, window)
    bar:SetPoint("TOPLEFT", MARGIN, -HEADER_HEIGHT)
    bar:SetPoint("TOPRIGHT", -MARGIN, -HEADER_HEIGHT)
    bar:SetHeight(TABS_HEIGHT)
    window.tabBar = bar
    local baseline = bar:CreateTexture(nil, "BACKGROUND")
    baseline:SetColorTexture(1, 1, 1, 0.05)
    baseline:SetHeight(1)
    baseline:SetPoint("BOTTOMLEFT")
    baseline:SetPoint("BOTTOMRIGHT")
    local line = bar:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(unpack(C.accent))
    line:SetHeight(2)
    window.tabUnderline = line

    for index, entry in ipairs(TABS) do
        local button = CreateFrame("Button", nil, bar)
        button:SetHeight(TABS_HEIGHT)
        button.text = UI.Text(button, T.body, C.muted)
        button.text:SetPoint("CENTER", 0, 1)
        W.Bind(button.text, entry.key)
        button:SetScript("OnClick", function() ShowPage(entry.id, true) end)
        button:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(C.text)) end)
        button:SetScript("OnLeave", function(self)
            if currentPage ~= pages[entry.id] then self.text:SetTextColor(unpack(C.muted)) end
        end)
        tabButtons[index] = button
    end
    LayoutTabs()
    W.AfterLocale(LayoutTabs)
end

local function CreatePreviewToggle(header)
    local toggle = CreateFrame("Button", nil, header)
    toggle:SetHeight(24)
    local switch = W.CreateSwitch(toggle)
    switch:SetPoint("RIGHT")
    local label = UI.Text(toggle, T.label, C.muted)
    label:SetPoint("RIGHT", switch, "LEFT", -8, 0)
    W.Bind(label, "PREVIEW")
    local function Fit() toggle:SetWidth(label:GetStringWidth() + 8 + 26) end
    Fit()
    W.OnLocale(Fit)
    toggle:SetScript("OnClick", function()
        previewStartedHere = not ns.TestMode.active
        ns.TestMode.Toggle()
    end)
    toggle:SetScript("OnEnter", function(self)
        label:SetTextColor(unpack(C.text))
        W.SetSwitchHover(switch, true)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.PREVIEW_DESC, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function()
        label:SetTextColor(unpack(C.muted))
        W.SetSwitchHover(switch, false)
        GameTooltip:Hide()
    end)
    ns.Listen("TEST_MODE_CHANGED", function(active) W.SetSwitch(switch, active, true) end)
    W.SetSwitch(switch, ns.TestMode.active, false)
    return toggle
end

local function CreateHeader()
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    header:EnableMouse(true)
    W.DragHandle(header, function() window:StartMoving() end, function() window:StopMovingOrSizing() end)

    local glyph = UI.AddonGlyph(header, HEADER_GLYPH_HEIGHT)
    glyph:SetPoint("LEFT", MARGIN, -2)
    local title = UI.BoldText(header, T.title, C.text)
    title:SetPoint("LEFT", glyph, "RIGHT", HEADER_GLYPH_GAP, 0)
    title:SetText(ns.TITLE)
    local version = UI.Text(header, T.caption, C.faint)
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 0)
    version:SetText(ns.VERSION)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", -MARGIN + 6, -2)
    local cross = UI.Text(close, 18, C.muted)
    cross:SetPoint("CENTER", 0, 1)
    cross:SetText("×")
    close:SetScript("OnClick", Options.Close)
    close:SetScript("OnEnter", function() cross:SetTextColor(unpack(C.text)) end)
    close:SetScript("OnLeave", function() cross:SetTextColor(unpack(C.muted)) end)

    local preview = CreatePreviewToggle(header)
    preview:SetPoint("RIGHT", close, "LEFT", -12, 0)
end

local function CreateAnimations()
    local open = window:CreateAnimationGroup()
    local fadeIn = open:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.16)
    fadeIn:SetSmoothing("OUT")
    local grow = open:CreateAnimation("Scale")
    grow:SetScaleFrom(0.97, 0.97)
    grow:SetScaleTo(1, 1)
    grow:SetDuration(0.18)
    grow:SetSmoothing("OUT")
    window.openAnimation = open

    local close = window:CreateAnimationGroup()
    local fadeOut = close:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.12)
    fadeOut:SetSmoothing("IN")
    close:SetScript("OnFinished", function() window:Hide() end)
    window.closeAnimation = close
end

local function CreateWindow()
    window = CreateFrame("Frame", "ReScrollOptionsFrame", UIParent)
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:Hide()
    UI.Fill(window, C.window)
    tinsert(UISpecialFrames, window:GetName())

    CreateHeader()
    CreateTabs()

    local body = CreateFrame("Frame", nil, window)
    body:SetPoint("TOPLEFT", MARGIN - CONTENT_INSET, -HEADER_HEIGHT - TABS_HEIGHT - BODY_GAP)
    body:SetPoint("BOTTOMRIGHT", -MARGIN + CONTENT_INSET, MARGIN)
    window.body = body

    CreateAnimations()
    window:SetScript("OnHide", function()
        if previewStartedHere then
            ns.TestMode.Stop()
            previewStartedHere = false
        end
        ns.Fire("OPTIONS_SHOWN", false)
    end)
end

function Options.IsOpen()
    return window ~= nil and window:IsShown()
end

function Options.Open(pageId)
    if not window then CreateWindow() end
    window.closeAnimation:Stop()
    if not window:IsShown() then
        window:Show()
        window.openAnimation:Restart()
        if not ns.TestMode.active and #ns.Status.records == 0 then
            previewStartedHere = true
            ns.TestMode.Start()
        end
        ns.Fire("OPTIONS_SHOWN", true)
    end
    ShowPage(pageId or currentPage and currentPage.id or ns.db.lastPage or DEFAULT_PAGE, false)
end

function Options.Close()
    if not window or not window:IsShown() then return end
    window.openAnimation:Stop()
    window.closeAnimation:Restart()
end

function Options.Toggle(pageId)
    if window and window:IsShown() and (not pageId or currentPage == pages[pageId]) then
        Options.Close()
    else
        Options.Open(pageId)
    end
end

ns.Listen("SETTING_CHANGED", function()
    if window and window:IsShown() and currentPage then
        RefreshPage(currentPage, true)
    end
end)

local function RegisterSettingsCategory()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    panel:Hide()
    local glyph = UI.AddonGlyph(panel, SETTINGS_GLYPH_HEIGHT)
    glyph:SetPoint("TOPLEFT", 16, -16)
    local title = UI.Text(panel, 20, C.text)
    title:SetPoint("LEFT", glyph, "RIGHT", HEADER_GLYPH_GAP, 0)
    title:SetText(ns.TITLE)
    local desc = UI.Text(panel, T.body, C.muted)
    desc:SetPoint("TOPLEFT", glyph, "BOTTOMLEFT", 0, -10)
    W.Bind(desc, "SETTINGS_DESC")
    local open = W.Button(panel, "SETTINGS_OPEN", function() Options.Open() end, "primary")
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    local category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
    Settings.RegisterAddOnCategory(category)
end

ns.Listen("LOGIN", RegisterSettingsCategory)
