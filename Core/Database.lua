local _, ns = ...

local DEFAULTS = {
    enabled = true,
    locale = "auto",
    visibility = "always",
    hideResting = false,
    readyCheck = true,
    expireMinutes = 5,
    lowerRanks = true,
    upgrades = true,
    groupBuffs = true,
    showEmpty = true,
    stock = 5,
    countBank = true,
    auction = true,
    priceStep = 20,
    auctionX = 0,
    auctionY = 0,
    bankX = 0,
    bankY = 0,
    dock = {},
    bank = true,
    bankAuto = false,
    iconSize = 36,
    perRow = 6,
    spacing = 4,
    grow = "RIGHT",
    showHeader = true,
    showCounts = true,
    barBackground = 92,
    panelBackground = 98,
    locked = false,
    position = { point = "CENTER", x = 0, y = -160 },
    minimap = { hide = false, angle = 235 },
    learned = {},
}

local CHAR_DEFAULTS = {
    families = {},
    order = {},
    stockOverride = {},
    buyRanks = {},
}

ns.DEFAULTS = DEFAULTS

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = ApplyDefaults(type(target[key]) == "table" and target[key] or {}, value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

ns.Listen("INIT", function()
    ReScrollDB = ApplyDefaults(ReScrollDB or {}, DEFAULTS)
    ReScrollCharDB = ApplyDefaults(ReScrollCharDB or {}, CHAR_DEFAULTS)
    ns.db = ReScrollDB
    ns.charDB = ReScrollCharDB
    ns.Fire("DB_READY")
end)

function ns.Set(key, value)
    if ns.db[key] == value then return end
    ns.db[key] = value
    ns.Fire("SETTING_CHANGED", key, value)
end

function ns.ResetSettings()
    local learned = ns.db.learned
    wipe(ns.db)
    ApplyDefaults(ns.db, DEFAULTS)
    ns.db.learned = learned
    wipe(ns.charDB)
    ApplyDefaults(ns.charDB, CHAR_DEFAULTS)
    ns.Fire("SETTING_CHANGED")
end
