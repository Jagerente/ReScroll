local _, ns = ...

local IsSecret = ns.IsSecret
local IsSpellKnown = C_SpellBook.IsSpellKnown

local Group = { providers = {}, selfSpells = {} }
ns.Group = Group

local REFRESH_DELAY = 0.3
local MAX_PARTY = 4
local MAX_RAID = 40

local providers, selfSpells = Group.providers, Group.selfSpells

local function BestAmountAt(ranks, level)
    local best = 0
    for _, rank in ipairs(ranks) do
        if rank.level <= level and rank.amount > best then best = rank.amount end
    end
    return best
end

local function Consider(unit)
    if not UnitExists(unit) or UnitIsUnit(unit, "player") then return end
    local connected = UnitIsConnected(unit)
    if IsSecret(connected) or not connected then return end
    local _, class = UnitClass(unit)
    local level = UnitLevel(unit)
    if IsSecret(class) or IsSecret(level) or not class then return end
    for buffKey, source in pairs(ns.BUFF_PROVIDERS) do
        if source.class == class and not source.talent then
            local amount = BestAmountAt(ns.CLASS_BUFFS[buffKey], level)
            local current = providers[buffKey]
            if amount > 0 and (not current or amount > current.amount) then
                providers[buffKey] = { amount = amount, name = UnitName(unit), class = class }
            end
        end
    end
end

local function ScanGroup()
    wipe(providers)
    if IsInRaid() then
        for index = 1, math.min(GetNumGroupMembers(), MAX_RAID) do
            Consider("raid" .. index)
        end
    elseif IsInGroup() then
        for index = 1, MAX_PARTY do
            Consider("party" .. index)
        end
    end
end

local function ScanSelf()
    wipe(selfSpells)
    local _, class = UnitClass("player")
    for buffKey, source in pairs(ns.BUFF_PROVIDERS) do
        if source.class == class then
            for _, rank in ipairs(ns.CLASS_BUFFS[buffKey]) do
                if rank.single and IsSpellKnown(rank.spell) then
                    local current = selfSpells[buffKey]
                    if not current or rank.amount > current.amount then selfSpells[buffKey] = rank end
                end
            end
        end
    end
end

local function Refresh()
    ScanGroup()
    ScanSelf()
    ns.Fire("GROUP_CHANGED")
end

local function RefreshSoon()
    ns.Schedule("group", REFRESH_DELAY, Refresh)
end

function Group.Provider(buffKey)
    return providers[buffKey]
end

function Group.SelfSpell(buffKey)
    return selfSpells[buffKey]
end

ns.Listen("LOGIN", function()
    ns.RegisterEvent("GROUP_ROSTER_UPDATE", RefreshSoon)
    ns.RegisterEvent("UNIT_LEVEL", RefreshSoon)
    ns.RegisterEvent("UNIT_CONNECTION", RefreshSoon)
    ns.RegisterEvent("SPELLS_CHANGED", RefreshSoon)
    ns.RegisterEvent("PLAYER_LEVEL_UP", RefreshSoon)
    Refresh()
end)
