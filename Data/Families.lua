local _, ns = ...

local ALL = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

ns.FAMILIES = {
    { key = "stamina", classes = ALL, coveredBy = "fortitude" },
    { key = "protection", classes = ALL },
    { key = "agility", classes = { "WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "DRUID" } },
    { key = "strength", classes = { "WARRIOR", "PALADIN", "ROGUE", "SHAMAN", "DRUID" } },
    { key = "intellect", classes = { "PALADIN", "HUNTER", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }, coveredBy = "intellect" },
    { key = "spirit", classes = { "PALADIN", "PRIEST", "SHAMAN", "MAGE", "DRUID" }, coveredBy = "divineSpirit" },
    { key = "familiar", classes = { "MAGE" }, label = "FAMILIAR" },
    { key = "arcaneAccuracy", classes = {} },
    { key = "arcanePower", classes = {} },
    { key = "arcaneFire", classes = {} },
    { key = "arcaneFrost", classes = {} },
    { key = "arcaneRecovery", classes = {} },
}

ns.UTILITIES = {
    { key = "liminalPassage" },
    { key = "reintegration" },
    { key = "unlocking" },
    { key = "minorEvocation" },
    { key = "polymorph" },
    { key = "confuseBeast" },
    { key = "rebukeElemental" },
    { key = "cryoblast" },
    { key = "comprehension" },
}

ns.BUFF_PROVIDERS = {
    fortitude = { class = "PRIEST" },
    intellect = { class = "MAGE" },
    divineSpirit = { class = "PRIEST", talent = true },
}
