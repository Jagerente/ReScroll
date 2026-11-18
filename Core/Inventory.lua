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

local function RanksDown(family, top, lowest, out)
    wipe(out)
    if not top then return out end
    for index = top.index, lowest, -1 do
        out[#out + 1] = family.ranks[index]
    end
    return out
end

function Inventory.OfferRanks(family, level, out)
    local top = Inventory.TopUsableRank(family, level)
    return RanksDown(family, top, ns.db.lowerRanks and 1 or (top and top.index), out)
end

function Inventory.StockRank(family, level)
    local top = Inventory.TopUsableRank(family, level or UnitLevel("player"))
    local picked = ns.charDB.buyRanks[family.key]
    if top and picked and picked < top.index and ns.db.lowerRanks then return family.ranks[picked] end
    return top
end

function Inventory.CountedRanks(family, level, grade, out)
    return RanksDown(family, Inventory.TopUsableRank(family, level), grade and grade.index or 1, out)
end

local counted = {}

function Inventory.StockCount(family, grade)
    local level = UnitLevel("player")
    grade = grade or Inventory.StockRank(family, level)
    local inBags, inBank, inMail = 0, 0, 0
    if not grade then return inBags, inBank, inMail end
    for _, rank in ipairs(Inventory.CountedRanks(family, level, grade, counted)) do
        inBags = inBags + Inventory.Count(rank.item)
        inBank = inBank + Inventory.BankCount(rank.item)
        inMail = inMail + Inventory.MailCount(rank.item)
    end
    return inBags, inBank, inMail
end

function Inventory.Stock(family, grade)
    local have, bank, inMail = Inventory.StockCount(family, grade)
    if not ns.db.countBank then bank = 0 end
    local need = Inventory.StockTarget(family) - have - bank - inMail
    return { have = have, bank = bank, mail = inMail, need = need }
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
            local ranks = Inventory.OfferRanks(family, level, {})
            local stocks = {}
            for index, rank in ipairs(ranks) do
                stocks[index] = Inventory.Stock(family, rank)
            end
            if stocks[1].need > 0 then
                out[#out + 1] = { family = family, ranks = ranks, stocks = stocks }
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
