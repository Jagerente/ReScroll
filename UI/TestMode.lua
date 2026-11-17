local _, ns = ...

local Status = ns.Status
local Catalog = ns.Catalog

local TestMode = { active = false, records = {}, chain = {} }
ns.TestMode = TestMode

local EXPIRING_SECONDS = 187
local SAMPLE_PROVIDER = { name = "Lumen", class = "PRIEST", amount = 0 }
local STATES = { Status.MISSING, Status.EXPIRING, Status.UPGRADE, Status.GROUP, Status.MISSING, Status.EMPTY }

local samples = {}

local function Sample(family, state)
    local record = samples[family.key]
    if not record then
        record = {}
        samples[family.key] = record
    end
    local ranks = family.ranks
    record.family, record.state, record.top = family, state, family.top
    record.rank = state ~= Status.EMPTY and family.top or nil
    record.activeRank = state == Status.UPGRADE and ranks[math.max(1, #ranks - 1)] or family.top
    record.expiration = GetTime() + EXPIRING_SECONDS
    record.provider = state == Status.GROUP and SAMPLE_PROVIDER or nil
    record.spell = nil
    return record
end

local function Build()
    wipe(TestMode.records)
    wipe(TestMode.chain)
    local pick = {}
    for _, family in ipairs(Catalog.ordered) do
        if Catalog.IsEnabled(family) then pick[#pick + 1] = family end
    end
    if #pick < #STATES then
        for _, family in ipairs(Catalog.ordered) do
            if #pick >= #STATES then break end
            if not Catalog.IsEnabled(family) then pick[#pick + 1] = family end
        end
    end
    for index, family in ipairs(pick) do
        local record = Sample(family, STATES[(index - 1) % #STATES + 1])
        TestMode.records[index] = record
        if Status.InChain(record) then TestMode.chain[#TestMode.chain + 1] = record end
    end
end

local function SetActive(active)
    if TestMode.active == active then return end
    TestMode.active = active
    if active then Build() end
    ns.Fire("TEST_MODE_CHANGED", active)
end

function TestMode.Start()
    SetActive(true)
end

function TestMode.Stop()
    SetActive(false)
end

function TestMode.Toggle()
    SetActive(not TestMode.active)
end

ns.Listen("FAMILIES_CHANGED", function()
    if not TestMode.active then return end
    Build()
    ns.Fire("TEST_MODE_CHANGED", true)
end)
