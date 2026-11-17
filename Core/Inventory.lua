local _, ns = ...

local Catalog = ns.Catalog
local GetItemCount = C_Item.GetItemCount

local Inventory = { bags = {}, total = {}, mail = {} }
ns.Inventory = Inventory

local bags, total, mail = Inventory.bags, Inventory.total, Inventory.mail

local function Arrived(item, grown)
    local waiting = mail[item]
    if not waiting or grown <= 0 then return end
    mail[item] = waiting > grown and waiting - grown or nil
end

local function Recount()
    local changed = false
    for _, family in ipairs(ns.FAMILIES) do
        for _, rank in ipairs(family.ranks) do
            local item = rank.item
            local inBags = GetItemCount(item, false) or 0
            local everywhere = GetItemCount(item, true, false, false, true) or inBags
            if bags[item] ~= inBags or total[item] ~= everywhere then
                if total[item] then Arrived(item, everywhere - total[item]) end
                bags[item], total[item] = inBags, everywhere
                changed = true
            end
        end
    end
    if changed then ns.Fire("INVENTORY_CHANGED") end
end
Inventory.Recount = Recount

function Inventory.Count(item)
    return bags[item] or 0
end

function Inventory.BankCount(item)
    return math.max(0, (total[item] or 0) - (bags[item] or 0))
end

function Inventory.TotalCount(item)
    return total[item] or 0
end

function Inventory.MailCount(item)
    return mail[item] or 0
end

function Inventory.AddBought(item, quantity, countBefore)
    local arrived = math.max(0, Inventory.TotalCount(item) - countBefore)
    local waiting = quantity - arrived
    if waiting <= 0 then return end
    mail[item] = Inventory.MailCount(item) + waiting
    ns.Fire("INVENTORY_CHANGED")
end

function Inventory.Cooldown(item)
    local start, duration = C_Container.GetItemCooldown(item)
    if ns.IsSecret(start) or ns.IsSecret(duration) then return 0, 0 end
    return start or 0, duration or 0
end

function Inventory.StockTarget(family)
    return ns.charDB.stockOverride[family.key] or ns.db.stock
end

function Inventory.TopUsableRank(family, level)
    local best
    for _, rank in ipairs(family.ranks) do
        if rank.level <= level then best = rank end
    end
    return best
end

function Inventory.StockRanks(family, level, out)
    wipe(out)
    local top = Inventory.TopUsableRank(family, level)
    if not top then return out end
    local lowest = ns.db.lowerRanks and 1 or top.index
    for index = top.index, lowest, -1 do
        out[#out + 1] = family.ranks[index]
    end
    return out
end

local stockRanks = {}

function Inventory.StockCount(family)
    local inBags, inBank, inMail = 0, 0, 0
    for _, rank in ipairs(Inventory.StockRanks(family, UnitLevel("player"), stockRanks)) do
        inBags = inBags + Inventory.Count(rank.item)
        inBank = inBank + Inventory.BankCount(rank.item)
        inMail = inMail + Inventory.MailCount(rank.item)
    end
    return inBags, inBank, inMail
end

local function CastsItself(family, rank)
    local own = family.coveredBy and ns.Group.SelfSpell(family.coveredBy)
    return own ~= nil and own.amount >= rank.amount
end

function Inventory.Restockable(family, level)
    local top = Catalog.IsEnabled(family) and Inventory.TopUsableRank(family, level)
    return top and not CastsItself(family, top) and top or nil
end

function Inventory.GetShoppingList(out)
    wipe(out)
    local level = UnitLevel("player")
    for _, family in ipairs(Catalog.ordered) do
        if Inventory.Restockable(family, level) then
            local have, bank, inMail = Inventory.StockCount(family)
            if not ns.db.countBank then bank = 0 end
            local need = Inventory.StockTarget(family) - have - bank - inMail
            if need > 0 then
                local ranks = Inventory.StockRanks(family, level, {})
                out[#out + 1] = { family = family, ranks = ranks, need = need, have = have, bank = bank, mail = inMail }
            end
        end
    end
    return out
end

local MAIL_ATTACHMENTS = 16
local inbox = {}

local function CountInbox()
    wipe(inbox)
    for index = 1, GetInboxNumItems() do
        local _, _, _, _, _, cod, _, attachments = GetInboxHeaderInfo(index)
        if attachments and attachments > 0 and (cod or 0) == 0 then
            for slot = 1, MAIL_ATTACHMENTS do
                local _, item, _, count = GetInboxItem(index, slot)
                if item and total[item] then inbox[item] = (inbox[item] or 0) + count end
            end
        end
    end
end

local function OnInboxUpdate()
    Recount()
    CountInbox()
    local changed = false
    for item, count in pairs(inbox) do
        if count > Inventory.MailCount(item) then
            mail[item] = count
            changed = true
        end
    end
    if changed then ns.Fire("INVENTORY_CHANGED") end
end

ns.Listen("LOGIN", function()
    ns.RegisterEvent("BAG_UPDATE_DELAYED", Recount)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", Recount)
    ns.RegisterEvent("BANKFRAME_CLOSED", Recount)
    ns.RegisterEvent("MAIL_INBOX_UPDATE", OnInboxUpdate)
    Recount()
end)
