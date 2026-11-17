local _, ns = ...

local Catalog = ns.Catalog
local Auras = ns.Auras
local Inventory = ns.Inventory
local Group = ns.Group
local Learning = ns.Learning
local GetTime = GetTime

local Status = { records = {}, chain = {}, needed = 0 }
ns.Status = Status

local PENDING_SECONDS = 3
local RECHECK_PAD = 0.05
local SECONDS_PER_MINUTE = 60

Status.MISSING = "missing"
Status.EXPIRING = "expiring"
Status.UPGRADE = "upgrade"
Status.SELF = "self"
Status.GROUP = "group"
Status.EMPTY = "empty"

local CHAINED = { missing = true, expiring = true, upgrade = true, self = true }

local pool = {}
local pending = {}
local snoozed = {}
local recheckTimer
local nextCheck

local function Record(family)
    local record = pool[family.key]
    if not record then
        record = { family = family }
        pool[family.key] = record
    end
    record.state, record.rank, record.spell, record.expiration = nil, nil, nil, nil
    record.provider, record.activeRank = nil, nil
    return record
end

local function OwnedRank(family, level)
    local lowerAllowed = ns.db.lowerRanks
    local top = Inventory.TopUsableRank(family, level)
    for index = top.index, 1, -1 do
        local rank = family.ranks[index]
        if Inventory.Count(rank.item) > 0 then return rank end
        if not lowerAllowed then return nil end
    end
end

local function CoverAmount(buffKey)
    local best = 0
    if not buffKey then return best end
    for _, rank in ipairs(ns.CLASS_BUFFS[buffKey]) do
        if Auras.Expiration(rank.spell) and rank.amount > best then best = rank.amount end
    end
    return best
end

local function ActiveRank(family)
    for index = #family.ranks, 1, -1 do
        local rank = family.ranks[index]
        local expiration = Auras.Expiration(rank.spell)
        if expiration then return rank, expiration end
    end
end

local function NoteCheck(at)
    if not nextCheck or at < nextCheck then nextCheck = at end
end

local function EvaluateActive(record, owned, activeRank, expiration, now)
    local threshold = ns.db.expireMinutes * SECONDS_PER_MINUTE
    record.activeRank, record.expiration = activeRank, expiration
    if expiration > 0 and expiration - now <= threshold then
        record.state = Status.EXPIRING
        if owned and owned.amount >= activeRank.amount then record.rank = owned end
        return true
    end
    if expiration > 0 then NoteCheck(expiration - threshold) end
    if ns.db.upgrades and owned and owned.amount > activeRank.amount then
        record.state = Status.UPGRADE
        record.rank = owned
        return true
    end
    return false
end

local function EvaluateMissing(record, family, owned, wanted)
    local buffKey = family.coveredBy
    local own = buffKey and Group.SelfSpell(buffKey)
    if own and own.amount >= wanted then
        record.state = Status.SELF
        record.spell = own.spell
        return true
    end
    local provider = ns.db.groupBuffs and buffKey and Group.Provider(buffKey)
    if provider and provider.amount >= wanted then
        record.state = Status.GROUP
        record.provider = provider
        record.rank = owned
        return true
    end
    record.rank = owned
    if owned then
        record.state = Status.MISSING
        return true
    end
    record.state = Status.EMPTY
    return ns.db.showEmpty
end

local function Evaluate(family, level, now)
    if not Catalog.IsEnabled(family) or snoozed[family.key] then return nil end
    local top = Inventory.TopUsableRank(family, level)
    if not top then return nil end
    local owned = OwnedRank(family, level)
    local wanted = (owned or top).amount
    if CoverAmount(family.coveredBy) >= wanted or Learning.IsBlocked(family) then return nil end
    local pendingUntil = pending[family.key]
    if pendingUntil and pendingUntil > now then
        NoteCheck(pendingUntil)
        return nil
    end
    local record = Record(family)
    record.top = top
    local activeRank, expiration = ActiveRank(family)
    if activeRank then
        return EvaluateActive(record, owned, activeRank, expiration, now) and record or nil
    end
    return EvaluateMissing(record, family, owned, wanted) and record or nil
end

local function Schedule()
    if recheckTimer then
        recheckTimer:Cancel()
        recheckTimer = nil
    end
    if not nextCheck then return end
    recheckTimer = C_Timer.NewTimer(math.max(0, nextCheck - GetTime()) + RECHECK_PAD, Status.Update)
end

function Status.CanUse(record)
    return record.rank ~= nil or record.spell ~= nil
end

function Status.InChain(record)
    return CHAINED[record.state] == true and Status.CanUse(record)
end

function Status.Update()
    local records, chain = Status.records, Status.chain
    wipe(records)
    wipe(chain)
    nextCheck = nil
    local needed = 0
    local level, now = UnitLevel("player"), GetTime()
    for _, family in ipairs(Catalog.ordered) do
        local record = Evaluate(family, level, now)
        if record then
            records[#records + 1] = record
            if record.state ~= Status.GROUP then needed = needed + 1 end
            if Status.InChain(record) then chain[#chain + 1] = record end
        end
    end
    Status.needed = needed
    Schedule()
    ns.Fire("STATUS_CHANGED")
end

function Status.UpdateSoon()
    ns.Schedule("status", 0, Status.Update)
end

function Status.Snooze(family)
    snoozed[family.key] = true
    Status.Update()
end

local function FamiliesForSpell(spellID, out)
    wipe(out)
    local scroll = Catalog.scrollSpells[spellID]
    if scroll then
        out[1] = scroll.family
        return out
    end
    local buff = Catalog.buffSpells[spellID]
    if not buff then return out end
    for _, family in ipairs(ns.FAMILIES) do
        if family.coveredBy == buff.buff then out[#out + 1] = family end
    end
    return out
end

local applied = {}

local function OnCastSucceeded(_, _, spellID)
    if ns.IsSecret(spellID) then return end
    FamiliesForSpell(spellID, applied)
    if #applied == 0 then return end
    local pendingUntil = GetTime() + PENDING_SECONDS
    for _, family in ipairs(applied) do
        pending[family.key] = pendingUntil
    end
    Status.Update()
end

local function ClearSnoozes()
    if not next(snoozed) then return end
    wipe(snoozed)
    Status.UpdateSoon()
end

for _, message in ipairs({ "AURAS_CHANGED", "INVENTORY_CHANGED", "GROUP_CHANGED", "FAMILIES_CHANGED", "LEARNED" }) do
    ns.Listen(message, Status.UpdateSoon)
end

local STATUS_SETTINGS = {
    expireMinutes = true, lowerRanks = true, upgrades = true, groupBuffs = true, showEmpty = true, stock = true,
}

ns.Listen("SETTING_CHANGED", function(key)
    if key == nil or STATUS_SETTINGS[key] then Status.UpdateSoon() end
end)

ns.Listen("LOGIN", function()
    ns.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", OnCastSucceeded)
    ns.RegisterEvent("PLAYER_LEVEL_UP", Status.UpdateSoon)
    ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", ClearSnoozes)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", ClearSnoozes)
    Status.Update()
end)
