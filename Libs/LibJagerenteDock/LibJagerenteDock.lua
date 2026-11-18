local _, ns = ...

local NAME, MINOR = "LibJagerenteDock", 2

local lib = _G[NAME]
if lib and lib.minor >= MINOR then
    ns.Dock = lib
    return
end

lib = lib or {}
lib.minor = MINOR
lib.addons = lib.addons or {}
lib.panels = lib.panels or {}
lib.watched = lib.watched or {}
lib.listeners = lib.listeners or {}
lib.members, lib.LEGACY, lib.probes, lib.probing = nil, nil, nil, nil
_G[NAME] = lib
ns.Dock = lib

local HOST = "host"
local GAP = 4
local FREE_INSET = 14
local DEFAULT_ORDER = 100
local FIRST_SIDE, NEXT_SIDE = "RIGHT", "BELOW"

lib.HOST = HOST
lib.SIDES = { "RIGHT", "LEFT", "BELOW", "ABOVE" }

local POINTS = {
    RIGHT = { "TOPLEFT", "TOPRIGHT", GAP, 0 },
    LEFT = { "TOPRIGHT", "TOPLEFT", -GAP, 0 },
    BELOW = { "TOPLEFT", "BOTTOMLEFT", 0, -GAP },
    ABOVE = { "BOTTOMLEFT", "TOPLEFT", 0, GAP },
}

local EMPTY = {}

local function VisibleHost(names)
    for _, name in ipairs(names) do
        local frame = _G[name]
        if frame and frame:IsVisible() then return frame end
    end
end

local function ByOrder(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.name < b.name
end

local function Newer(a, b)
    if a.at ~= b.at then return a.at > b.at end
    return a.name < b.name
end

local function HasSlot(name, slot)
    local member = lib.addons[name]
    return member ~= nil and member.slots[slot] == true
end

local function ValidPlacement(name, slot, placement)
    if type(placement) ~= "table" or not POINTS[placement.side] then return false end
    local target = placement.target
    return target == HOST or (target ~= name and HasSlot(target, slot))
end

local function Choice(member, slot, override)
    local placement
    if override and override.name == member.name then
        placement = override.placement
    else
        placement = member.placement and member.placement(slot)
    end
    if ValidPlacement(member.name, slot, placement) then return placement end
end

local function Reaches(edges, from, goal)
    local seen = {}
    local current = from
    while current and current ~= HOST and not seen[current] do
        if current == goal then return true end
        seen[current] = true
        local edge = edges[current]
        current = edge and edge.target
    end
    return false
end

local function OldestInCycle(edges, start)
    local oldest = edges[start]
    local current = edges[start].target
    while current ~= start do
        local edge = edges[current]
        if Newer(oldest, edge) then oldest = edge end
        current = edge.target
    end
    return oldest
end

local function BreakCycles(edges, autos)
    for name in pairs(edges) do
        local edge = edges[name]
        if edge and edge.target ~= HOST and Reaches(edges, edge.target, name) then
            local oldest = OldestInCycle(edges, name)
            edges[oldest.name] = nil
            autos[#autos + 1] = lib.addons[oldest.name]
            return BreakCycles(edges, autos)
        end
    end
end

local function Edges(slot, override)
    local edges, autos = {}, {}
    for name, member in pairs(lib.addons) do
        if member.slots[slot] then
            local placement = Choice(member, slot, override)
            if placement then
                edges[name] = { name = name, target = placement.target, side = placement.side, at = placement.at or 0 }
            else
                autos[#autos + 1] = member
            end
        end
    end
    BreakCycles(edges, autos)
    table.sort(autos, ByOrder)
    local previous
    for _, member in ipairs(autos) do
        edges[member.name] = {
            name = member.name,
            target = previous or HOST,
            side = previous and NEXT_SIDE or FIRST_SIDE,
            at = 0,
        }
        previous = member.name
    end
    return edges
end

local function Children(edges)
    local children = {}
    for _, edge in pairs(edges) do
        local bySide = children[edge.target]
        if not bySide then
            bySide = {}
            children[edge.target] = bySide
        end
        local list = bySide[edge.side]
        if not list then
            list = {}
            bySide[edge.side] = list
        end
        list[#list + 1] = edge
    end
    return children
end

local function ChildList(children, key, side)
    local list = {}
    local bySide = children[key]
    for _, edge in ipairs(bySide and bySide[side] or EMPTY) do list[#list + 1] = edge end
    return list
end

local function Assign(edges, shown)
    local children = Children(edges)
    local result = {}

    local function PlaceGroup(parent, side, queue)
        table.sort(queue, Newer)
        while #queue > 0 do
            local edge = table.remove(queue, 1)
            if shown(edge.name) then
                result[edge.name] = { parent = parent, side = side }
                for _, childSide in ipairs(lib.SIDES) do
                    local list = ChildList(children, edge.name, childSide)
                    if childSide == side then
                        for _, rest in ipairs(queue) do list[#list + 1] = rest end
                    end
                    PlaceGroup(edge.name, childSide, list)
                end
                return
            end
            for _, childSide in ipairs(lib.SIDES) do
                for _, child in ipairs(ChildList(children, edge.name, childSide)) do queue[#queue + 1] = child end
            end
            table.sort(queue, Newer)
        end
    end

    for _, side in ipairs(lib.SIDES) do
        PlaceGroup(HOST, side, ChildList(children, HOST, side))
    end
    return result
end

local function Anchor(panel, anchor, side)
    local frame = panel.frame
    local x, y = 0, 0
    if panel.offset then x, y = panel.offset() end
    frame:ClearAllPoints()
    if not anchor then
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -FREE_INSET + x, y)
        return
    end
    local point = POINTS[side]
    frame:SetPoint(point[1], anchor, point[2], point[3] + x, point[4] + y)
end

local function ShownGroups()
    local groups = {}
    for frame, panel in pairs(lib.panels) do
        if frame:IsShown() then
            local group = groups[panel.slot]
            if not group then
                group = { panels = {} }
                groups[panel.slot] = group
            end
            group.host = group.host or VisibleHost(panel.hosts)
            group.panels[panel.addon] = panel
        end
    end
    return groups
end

local function PlaceSlot(slot, group)
    local function Shown(name) return group.panels[name] ~= nil end
    for name, place in pairs(Assign(Edges(slot), Shown)) do
        local anchor = group.host
        if place.parent ~= HOST then anchor = group.panels[place.parent].frame end
        Anchor(group.panels[name], anchor, place.side)
    end
end

function lib:Layout()
    for slot, group in pairs(ShownGroups()) do
        PlaceSlot(slot, group)
    end
end

function lib:Watch(frame)
    if self.watched[frame] then return end
    self.watched[frame] = true
    local function Changed() lib:Layout() end
    frame:HookScript("OnShow", Changed)
    frame:HookScript("OnHide", Changed)
    frame:HookScript("OnSizeChanged", Changed)
end

function lib:Notify()
    for _, listener in ipairs(self.listeners) do listener() end
end

function lib:OnChange(listener)
    self.listeners[#self.listeners + 1] = listener
end

function lib:Join(addon, opts)
    local slots = {}
    for _, slot in ipairs(opts.slots) do slots[slot] = true end
    self.addons[addon] = { name = addon, order = opts.order or DEFAULT_ORDER, slots = slots, placement = opts.placement }
    self:Changed()
end

function lib:Register(frame, opts)
    if not self.addons[opts.addon] then self:Join(opts.addon, { slots = { opts.slot } }) end
    self.panels[frame] = { frame = frame, addon = opts.addon, slot = opts.slot, hosts = opts.hosts, offset = opts.offset }
    self:Watch(frame)
end

function lib:Changed()
    self:Layout()
    self:Notify()
end

function lib:Host(frame)
    local panel = self.panels[frame]
    return panel and VisibleHost(panel.hosts)
end

function lib:Family(slot)
    local names = {}
    for name, member in pairs(self.addons) do
        if member.slots[slot] then names[#names + 1] = member end
    end
    table.sort(names, ByOrder)
    for index, member in ipairs(names) do names[index] = member.name end
    return names
end

function lib:CanAttach(addon, slot, target)
    if target == HOST then return true end
    if target == addon or not HasSlot(target, slot) then return false end
    local override = { name = addon, placement = { target = target, side = FIRST_SIDE } }
    local edges = {}
    for name, member in pairs(self.addons) do
        if member.slots[slot] then
            local placement = Choice(member, slot, override)
            if placement then edges[name] = { name = name, target = placement.target } end
        end
    end
    return not Reaches(edges, target, addon)
end

local function Everyone() return true end

function lib:Place(addon, slot)
    local places = Assign(Edges(slot), Everyone)
    local place = places[addon]
    if not place then return nil end
    local member = self.addons[addon]
    local wanted = member and Choice(member, slot)
    local takenBy
    if wanted and (wanted.target ~= place.parent or wanted.side ~= place.side) then
        for name, other in pairs(places) do
            if name ~= addon and other.parent == wanted.target and other.side == wanted.side then takenBy = name end
        end
    end
    return place.parent, place.side, takenBy
end
