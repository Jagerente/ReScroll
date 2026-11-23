local _, ns = ...

local Catalog = {
    byKey = {}, byItem = {}, scrollSpells = {}, buffSpells = {},
    all = {}, ordered = {}, utilities = {}, restocked = {},
}
ns.Catalog = Catalog

local ANY_CLASS = -1
local NAME_DELAY = 0.2

local playerClass
local playerClassBit = 0

local function Attach(family)
    family.ranks = ns.SCROLLS[family.key]
    family.top = family.ranks[#family.ranks]
    family.classMask = family.top.classMask
    Catalog.byKey[family.key] = family
    Catalog.all[#Catalog.all + 1] = family
    for index, rank in ipairs(family.ranks) do
        rank.index = index
        Catalog.byItem[rank.item] = family
    end
end

for _, family in ipairs(ns.FAMILIES) do
    Attach(family)
    for _, rank in ipairs(family.ranks) do
        Catalog.scrollSpells[rank.spell] = { family = family, rank = rank }
    end
end

for _, family in ipairs(ns.UTILITIES) do
    family.utility = true
    Attach(family)
end

for buffKey, ranks in pairs(ns.CLASS_BUFFS) do
    for _, rank in ipairs(ranks) do
        Catalog.buffSpells[rank.spell] = { buff = buffKey, amount = rank.amount }
    end
end

local function ItemName(rank)
    return C_Item.GetItemNameByID(rank.item) or C_Spell.GetSpellName(rank.spell)
end

function Catalog.Name(family)
    if family.label then return ns.L[family.label] end
    if family.utility then return ItemName(family.ranks[1]) or family.key end
    return C_Spell.GetSpellName(family.top.spell) or family.key
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }

function Catalog.RomanRank(rank)
    return ROMAN[rank.index] or tostring(rank.index)
end

function Catalog.RankName(family, rank)
    if family.utility then return ItemName(rank) or family.key end
    if family.label then return C_Spell.GetSpellName(rank.spell) or Catalog.Name(family) end
    if #family.ranks == 1 then return Catalog.Name(family) end
    return Catalog.Name(family) .. " " .. Catalog.RomanRank(rank)
end

function Catalog.Icon(family, rank)
    return C_Item.GetItemIconByID((rank or family.top).item)
end

function Catalog.IsAvailable(family)
    local mask = family.classMask
    return mask == ANY_CLASS or bit.band(mask, playerClassBit) ~= 0
end

local function IsDefaultFor(family, class)
    for _, candidate in ipairs(family.classes or {}) do
        if candidate == class then return true end
    end
    return false
end

function Catalog.IsEnabled(family)
    local choice = ns.charDB.families[family.key]
    if choice == nil then return IsDefaultFor(family, playerClass) end
    return choice
end

function Catalog.SetEnabled(family, enabled)
    ns.charDB.families[family.key] = enabled
    ns.Fire("FAMILIES_CHANGED")
end

local function IsBuffKey(key)
    local family = Catalog.byKey[key]
    return family ~= nil and not family.utility
end

local function FillRestocked()
    local restocked = Catalog.restocked
    wipe(restocked)
    for _, family in ipairs(Catalog.ordered) do restocked[#restocked + 1] = family end
    for _, family in ipairs(Catalog.utilities) do restocked[#restocked + 1] = family end
end

local function FillUtilities()
    wipe(Catalog.utilities)
    for _, family in ipairs(ns.UTILITIES) do
        if Catalog.IsAvailable(family) then Catalog.utilities[#Catalog.utilities + 1] = family end
    end
end

local function Normalize()
    local order, seen = ns.charDB.order, {}
    for index = #order, 1, -1 do
        local key = order[index]
        if not IsBuffKey(key) or seen[key] then
            table.remove(order, index)
        else
            seen[key] = true
        end
    end
    for _, family in ipairs(ns.FAMILIES) do
        if not seen[family.key] then order[#order + 1] = family.key end
    end
    wipe(Catalog.ordered)
    for _, key in ipairs(order) do
        local family = Catalog.byKey[key]
        if Catalog.IsAvailable(family) then Catalog.ordered[#Catalog.ordered + 1] = family end
    end
    FillUtilities()
    FillRestocked()
end

local function IndexOf(list, value)
    for index, candidate in ipairs(list) do
        if candidate == value then return index end
    end
end

local function InsertionPoint(order, rest, toIndex)
    if #rest == 0 then return #order + 1 end
    if toIndex <= #rest then return IndexOf(order, rest[toIndex]) end
    return IndexOf(order, rest[#rest]) + 1
end

function Catalog.Move(key, toIndex)
    local order, rest = ns.charDB.order, {}
    for _, family in ipairs(Catalog.ordered) do
        if family.key ~= key then rest[#rest + 1] = family.key end
    end
    toIndex = math.max(1, math.min(#rest + 1, toIndex))
    local current = IndexOf(order, key)
    if current then table.remove(order, current) end
    table.insert(order, InsertionPoint(order, rest, toIndex), key)
    Normalize()
    ns.Fire("FAMILIES_CHANGED")
end

local function OnItemLoaded(item)
    if not Catalog.byItem[item] then return end
    ns.Schedule("names", NAME_DELAY, function() ns.Fire("NAMES_CHANGED") end)
end

ns.Listen("DB_READY", function()
    local _, class, classID = UnitClass("player")
    playerClass = class
    playerClassBit = classID and 2 ^ (classID - 1) or 0
    Normalize()
end)

ns.Listen("SETTING_CHANGED", function(key)
    if key == nil then
        Normalize()
        ns.Fire("FAMILIES_CHANGED")
    end
end)

ns.Listen("LOGIN", function()
    ns.RegisterEvent("ITEM_DATA_LOAD_RESULT", OnItemLoaded)
    for _, family in ipairs(Catalog.utilities) do
        for _, rank in ipairs(family.ranks) do
            C_Item.RequestLoadItemDataByID(rank.item)
        end
    end
end)
