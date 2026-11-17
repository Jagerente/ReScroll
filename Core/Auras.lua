local _, ns = ...

local Catalog = ns.Catalog
local IsSecret = ns.IsSecret
local GetAuraDataByIndex = C_UnitAuras.GetAuraDataByIndex
local GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID

local Auras = { active = {} }
ns.Auras = Auras

local MAX_AURAS = 255
local HELPFUL = "HELPFUL"

local active = Auras.active
local spellOfInstance = {}
local dirty = false

local function IsTracked(spellID)
    return Catalog.scrollSpells[spellID] ~= nil or Catalog.buffSpells[spellID] ~= nil or ns.Learning.candidates[spellID] == true
end

local function Store(aura)
    local spellID, instanceID, expiration = aura.spellId, aura.auraInstanceID, aura.expirationTime
    if IsSecret(spellID) or IsSecret(instanceID) or IsSecret(expiration) then
        dirty = true
        return false
    end
    if not IsTracked(spellID) then return false end
    spellOfInstance[instanceID] = spellID
    active[spellID] = expiration or 0
    return true
end

local function Forget(instanceID)
    local spellID = spellOfInstance[instanceID]
    if not spellID then return false end
    spellOfInstance[instanceID] = nil
    active[spellID] = nil
    return true
end

function Auras.Scan()
    wipe(active)
    wipe(spellOfInstance)
    dirty = false
    for index = 1, MAX_AURAS do
        local aura = GetAuraDataByIndex("player", index, HELPFUL)
        if not aura then break end
        Store(aura)
    end
    ns.Fire("AURAS_CHANGED")
end

local function ApplyUpdate(info)
    if not info or info.isFullUpdate then
        Auras.Scan()
        return
    end
    local changed = false
    if info.addedAuras then
        for _, aura in ipairs(info.addedAuras) do
            if Store(aura) then changed = true end
        end
    end
    if info.updatedAuraInstanceIDs then
        for _, instanceID in ipairs(info.updatedAuraInstanceIDs) do
            if spellOfInstance[instanceID] then
                local aura = GetAuraDataByAuraInstanceID("player", instanceID)
                if aura then Store(aura) end
                changed = true
            end
        end
    end
    if info.removedAuraInstanceIDs then
        for _, instanceID in ipairs(info.removedAuraInstanceIDs) do
            if Forget(instanceID) then changed = true end
        end
    end
    if changed then ns.Fire("AURAS_CHANGED") end
end

function Auras.Expiration(spellID)
    return active[spellID]
end

function Auras.IsReliable()
    return not dirty
end

function Auras.CollectHelpful(out)
    wipe(out)
    for index = 1, MAX_AURAS do
        local aura = GetAuraDataByIndex("player", index, HELPFUL)
        if not aura then break end
        local spellID = aura.spellId
        if not IsSecret(spellID) then out[spellID] = true end
    end
    return out
end

ns.Listen("LOGIN", function()
    ns.RegisterUnitEvent("UNIT_AURA", "player", function(_, info) ApplyUpdate(info) end)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", Auras.Scan)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if dirty then Auras.Scan() end
    end)
    Auras.Scan()
end)
