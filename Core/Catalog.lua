local _, ns = ...

local Catalog = { byKey = {}, scrollSpells = {}, buffSpells = {}, ordered = {} }
ns.Catalog = Catalog

local playerClass

for _, family in ipairs(ns.FAMILIES) do
    family.ranks = ns.SCROLLS[family.key]
    family.top = family.ranks[#family.ranks]
    Catalog.byKey[family.key] = family
    for index, rank in ipairs(family.ranks) do
        rank.index = index
        Catalog.scrollSpells[rank.spell] = { family = family, rank = rank }
    end
end

for buffKey, ranks in pairs(ns.CLASS_BUFFS) do
    for _, rank in ipairs(ranks) do
        Catalog.buffSpells[rank.spell] = { buff = buffKey, amount = rank.amount }
    end
end

function Catalog.Name(family)
    return C_Spell.GetSpellName(family.top.spell) or family.key
end

function Catalog.Icon(family, rank)
    return C_Item.GetItemIconByID((rank or family.top).item)
end

local function IsDefaultFor(family, class)
    for _, candidate in ipairs(family.classes) do
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

local function Normalize()
    local order, seen = ns.charDB.order, {}
    for index = #order, 1, -1 do
        local key = order[index]
        if not Catalog.byKey[key] or seen[key] then
            table.remove(order, index)
        else
            seen[key] = true
        end
    end
    for _, family in ipairs(ns.FAMILIES) do
        if not seen[family.key] then order[#order + 1] = family.key end
    end
    wipe(Catalog.ordered)
    for index, key in ipairs(order) do
        Catalog.ordered[index] = Catalog.byKey[key]
    end
end

function Catalog.Move(key, toIndex)
    local order = ns.charDB.order
    for index, candidate in ipairs(order) do
        if candidate == key then
            table.remove(order, index)
            break
        end
    end
    table.insert(order, math.max(1, math.min(#order + 1, toIndex)), key)
    Normalize()
    ns.Fire("FAMILIES_CHANGED")
end

ns.Listen("DB_READY", function()
    playerClass = select(2, UnitClass("player"))
    Normalize()
end)

ns.Listen("SETTING_CHANGED", function(key)
    if key == nil then
        Normalize()
        ns.Fire("FAMILIES_CHANGED")
    end
end)
