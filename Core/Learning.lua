local _, ns = ...

local IsSecret = ns.IsSecret
local GetTime = GetTime

local Learning = { candidates = {} }
ns.Learning = Learning

local RESPONSE_WINDOW = 1

local pending = { family = nil, deadline = 0, sent = false }
local bounced
local helpful = {}

local function RebuildCandidates()
    wipe(Learning.candidates)
    for _, spells in pairs(ns.db.learned) do
        for spellID in pairs(spells) do
            Learning.candidates[spellID] = true
        end
    end
end

local function IsOwnSpell(family, spellID)
    for _, rank in ipairs(family.ranks) do
        if rank.spell == spellID then return true end
    end
    return false
end

local function Arm(family, sent)
    pending.family = family
    pending.deadline = GetTime() + RESPONSE_WINDOW
    pending.sent = sent
end

local function Close()
    pending.family = nil
    pending.sent = false
end

function Learning.NoteUse(family)
    Arm(family, false)
end

local function Learn(family)
    local present = ns.Auras.CollectHelpful(helpful)
    local previous = ns.db.learned[family.key]
    local blockers = {}
    for spellID in pairs(present) do
        if not IsOwnSpell(family, spellID) and (not previous or previous[spellID]) then blockers[spellID] = true end
    end
    if not next(blockers) then
        for spellID in pairs(present) do
            if not IsOwnSpell(family, spellID) then blockers[spellID] = true end
        end
    end
    if not next(blockers) then return end
    ns.db.learned[family.key] = blockers
    RebuildCandidates()
    ns.Auras.Scan()
    ns.Fire("LEARNED", family)
end

local function OnCastSent(_, _, _, spellID)
    local family = pending.family
    if not family or IsSecret(spellID) then return end
    if IsOwnSpell(family, spellID) then
        Arm(family, true)
    elseif not pending.sent then
        Close()
    end
end

local function OnCastAnswered()
    if pending.family then Close() end
end

local function OnCastFailed(_, _, spellID)
    local family = pending.family
    if not family or IsSecret(spellID) or IsOwnSpell(family, spellID) then return end
    Close()
end

local function ResolveBounce()
    local family = bounced
    bounced = nil
    if not family or pending.family ~= family then return end
    Close()
    Learn(family)
end

local function OnError(_, message)
    if IsSecret(message) or message ~= SPELL_FAILED_AURA_BOUNCED then return end
    local family = pending.family
    if not family or GetTime() > pending.deadline then return end
    bounced = family
    ns.Schedule("learn", 0, ResolveBounce)
end

function Learning.IsBlocked(family)
    local blockers = ns.db.learned[family.key]
    if not blockers or not next(blockers) then return false end
    for spellID in pairs(blockers) do
        if not ns.Auras.Expiration(spellID) then return false end
    end
    return true
end

function Learning.Count()
    local count = 0
    for _ in pairs(ns.db.learned) do count = count + 1 end
    return count
end

function Learning.Forget()
    wipe(ns.db.learned)
    RebuildCandidates()
    ns.Auras.Scan()
    ns.Fire("LEARNED")
end

ns.Listen("DB_READY", RebuildCandidates)
ns.Listen("LOGIN", function()
    ns.RegisterEvent("UI_ERROR_MESSAGE", OnError)
    ns.RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player", OnCastSent)
    ns.RegisterUnitEvent("UNIT_SPELLCAST_START", "player", OnCastAnswered)
    ns.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", OnCastAnswered)
    ns.RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player", OnCastFailed)
    ns.RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player", OnCastFailed)
end)
