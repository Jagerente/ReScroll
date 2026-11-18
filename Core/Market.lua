local _, ns = ...

local Inventory = ns.Inventory

local Market = { open = false, entries = {} }
ns.Market = Market

Market.QUEUED = "queued"
Market.SEARCHING = "searching"
Market.READY = "ready"
Market.NONE = "none"
Market.BUYING = "buying"
Market.CONFIRM = "confirm"
Market.POOR = "poor"
Market.RAISED = "raised"
Market.ENOUGH = "enough"

local COMMODITY, ITEM = "commodity", "item"
local SEARCH_TIMEOUT = 6
local PURCHASE_TIMEOUT = 10
local RESEARCH_DELAY = 0.5
local PERCENT = 100

local entries = Market.entries
local byFamily = {}
local byItem = {}
local queue = {}
local shopping = {}
local keep = {}
local seen = {}
local searching
local buying
local searchTimer, purchaseTimer

local SORTS = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }

local function Changed()
    ns.Fire("MARKET_CHANGED")
end

local function CancelTimer(timer)
    if timer then timer:Cancel() end
end

local function Busy(entry)
    return entry.status == Market.BUYING or entry.status == Market.CONFIRM
end

local function Ceiling(base)
    return base * (1 + ns.db.priceStep / PERCENT)
end

function Market.IsSettled(offer)
    return offer.status ~= Market.QUEUED and offer.status ~= Market.SEARCHING
end

local function Available(offer)
    return offer.status == Market.READY or not Market.IsSettled(offer)
end

local function ChosenOffer(entry)
    local index = ns.charDB.buyRanks[entry.family.key]
    for _, offer in ipairs(entry.offers) do
        if offer.rank.index == index and Available(offer) then return offer end
    end
    for _, offer in ipairs(entry.offers) do
        if Available(offer) then return offer end
    end
end

function Market.SeenPrice(item)
    return seen[item]
end

function Market.IsRaised(offer)
    local first = seen[offer.item]
    return first ~= nil and offer.base > Ceiling(first)
end

local function ShowStock(entry, offer)
    local source = offer or entry.offers[1]
    entry.need, entry.have, entry.bank, entry.mail = source.need, source.have, source.bank, source.mail
end

local function Settle(entry)
    if Busy(entry) then return end
    local offer = ChosenOffer(entry)
    entry.offer = offer
    ShowStock(entry, offer)
    if not offer then
        entry.status = Market.NONE
    elseif not Market.IsSettled(offer) then
        entry.status = Market.SEARCHING
    elseif offer.need <= 0 then
        entry.status = Market.ENOUGH
    elseif offer.nextCost > GetMoney() then
        entry.status = Market.POOR
    elseif Market.IsRaised(offer) then
        entry.status = Market.RAISED
    else
        entry.status = Market.READY
    end
end

local function Pump()
    if searching or not Market.open or #queue == 0 then return end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    local offer = table.remove(queue, 1)
    if byItem[offer.item] ~= offer then return Pump() end
    searching = offer
    offer.status = Market.SEARCHING
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(offer.item), SORTS, false)
    CancelTimer(searchTimer)
    searchTimer = C_Timer.NewTimer(SEARCH_TIMEOUT, function()
        if searching ~= offer then return end
        searching = nil
        offer.status = Market.NONE
        Settle(offer.entry)
        Changed()
        Pump()
    end)
    Changed()
end

local function Enqueue(offer)
    if not Market.IsSettled(offer) then return end
    offer.status = Market.QUEUED
    queue[#queue + 1] = offer
end

local function Research(entry)
    for _, offer in ipairs(entry.offers) do
        Enqueue(offer)
    end
    Settle(entry)
end

local function FinishSearch(offer)
    if searching == offer then
        searching = nil
        CancelTimer(searchTimer)
    end
    Settle(offer.entry)
    Changed()
    Pump()
end

local function Priced(offer, quantity, cost, base, beyond)
    offer.quantity, offer.cost = quantity, cost
    offer.unitCost = quantity > 0 and cost / quantity or base or 0
    offer.base, offer.beyond = base or 0, beyond
    if base and not seen[offer.item] then seen[offer.item] = base end
end

local function ReadCommodities(offer)
    local need = offer.need
    local quantity, cost, base, beyond = 0, 0, nil, nil
    for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(offer.item) do
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(offer.item, index)
        local available = result and result.quantity - result.numOwnerItems or 0
        if available > 0 then
            base = base or result.unitPrice
            if quantity >= need then break end
            if result.unitPrice > Ceiling(base) then
                beyond = result.unitPrice
                break
            end
            local take = math.min(need - quantity, available)
            quantity = quantity + take
            cost = cost + take * result.unitPrice
        end
    end
    offer.kind = COMMODITY
    Priced(offer, quantity, cost, base, beyond)
    offer.nextCost = cost
    offer.unitPrice = quantity > 0 and math.ceil(cost / quantity) or 0
    offer.status = base and Market.READY or Market.NONE
end

local function UnitPrice(lot)
    return lot.buyoutAmount / lot.quantity
end

local function ByUnitPrice(a, b)
    return UnitPrice(a) < UnitPrice(b)
end

local function ReadItems(offer, itemKey)
    local need = offer.need
    local lots = {}
    for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
        if result and result.buyoutAmount and not result.containsOwnerItem then lots[#lots + 1] = result end
    end
    table.sort(lots, ByUnitPrice)
    local auctions, quantity, cost = {}, 0, 0
    local base = lots[1] and UnitPrice(lots[1])
    local beyond
    for _, lot in ipairs(lots) do
        if quantity >= need then break end
        if UnitPrice(lot) > Ceiling(base) then
            beyond = UnitPrice(lot)
            break
        end
        auctions[#auctions + 1] = lot
        quantity = quantity + lot.quantity
        cost = cost + lot.buyoutAmount
    end
    offer.kind = ITEM
    offer.auctions = auctions
    Priced(offer, quantity, cost, base, beyond)
    offer.nextCost = auctions[1] and auctions[1].buyoutAmount or 0
    offer.status = base and Market.READY or Market.NONE
end

local function Accepts(offer)
    if not offer or offer.status == Market.QUEUED then return false end
    local entry = offer.entry
    return not (Busy(entry) and entry.offer == offer)
end

local function OnCommodityResults(itemID)
    local offer = byItem[itemID]
    if not Accepts(offer) then return end
    ReadCommodities(offer)
    FinishSearch(offer)
end

local function OnItemResults(itemKey)
    local offer = itemKey and byItem[itemKey.itemID]
    if not Accepts(offer) then return end
    ReadItems(offer, itemKey)
    FinishSearch(offer)
end

local function SameRanks(entry, ranks)
    if #entry.offers ~= #ranks then return false end
    for index, rank in ipairs(ranks) do
        if entry.offers[index].rank ~= rank then return false end
    end
    return true
end

local function DropOffers(entry)
    for _, offer in ipairs(entry.offers) do
        if byItem[offer.item] == offer then byItem[offer.item] = nil end
    end
    wipe(entry.offers)
end

local function CopyStock(offer, stock)
    local changed = offer.need ~= stock.need
    offer.need, offer.have, offer.bank, offer.mail = stock.need, stock.have, stock.bank, stock.mail
    return changed
end

local function SetRanks(entry, wanted)
    DropOffers(entry)
    for index, rank in ipairs(wanted.ranks) do
        local offer = { entry = entry, rank = rank, item = rank.item }
        CopyStock(offer, wanted.stocks[index])
        entry.offers[index] = offer
        byItem[rank.item] = offer
    end
end

local function Restock(entry, wanted)
    local changed = false
    for index, offer in ipairs(entry.offers) do
        if CopyStock(offer, wanted.stocks[index]) then changed = true end
    end
    return changed
end

local function Sync(entry, wanted)
    local sameRanks = SameRanks(entry, wanted.ranks)
    local stale = not sameRanks or Restock(entry, wanted)
    if sameRanks then ShowStock(entry, entry.offer) end
    if not stale or Busy(entry) then return end
    if not sameRanks then SetRanks(entry, wanted) end
    Research(entry)
end

function Market.Rebuild()
    Inventory.GetShoppingList(shopping)
    wipe(entries)
    wipe(keep)
    for _, wanted in ipairs(shopping) do
        local key = wanted.family.key
        local entry = byFamily[key]
        if not entry then
            entry = { family = wanted.family, offers = {} }
            byFamily[key] = entry
        end
        Sync(entry, wanted)
        keep[key] = true
        entries[#entries + 1] = entry
    end
    for key, entry in pairs(byFamily) do
        if not keep[key] then
            DropOffers(entry)
            byFamily[key] = nil
        end
    end
    Changed()
    Pump()
end

function Market.Refresh()
    for _, entry in ipairs(entries) do
        if not Busy(entry) then Research(entry) end
    end
    Changed()
    Pump()
end

function Market.Pick(entry, rank)
    if Busy(entry) or not byItem[rank.item] or byItem[rank.item].status ~= Market.READY then return end
    local default = entry.offers[1].rank == rank
    ns.charDB.buyRanks[entry.family.key] = not default and rank.index or nil
    Settle(entry)
    Changed()
    ns.Fire("STOCK_CHANGED")
end

local function EndPurchase(entry, research)
    CancelTimer(purchaseTimer)
    if buying == entry then buying = nil end
    entry.status = Market.SEARCHING
    if research then
        C_Timer.After(RESEARCH_DELAY, function()
            if byFamily[entry.family.key] ~= entry then return end
            Research(entry)
            Changed()
            Pump()
        end)
    end
    Changed()
end

local function StartPurchaseTimer(entry)
    CancelTimer(purchaseTimer)
    purchaseTimer = C_Timer.NewTimer(PURCHASE_TIMEOUT, function()
        if buying == entry then EndPurchase(entry, true) end
    end)
end

local function BeginPurchase(entry)
    buying = entry
    entry.status = Market.BUYING
    entry.countBefore = Inventory.TotalCount(entry.offer.item)
    StartPurchaseTimer(entry)
    Changed()
end

function Market.Buy(entry)
    if buying or not entry then return end
    local offer = entry.offer
    if entry.status == Market.CONFIRM then
        C_AuctionHouse.ConfirmCommoditiesPurchase(offer.item, offer.quantity)
        BeginPurchase(entry)
        return
    end
    if entry.status == Market.RAISED then seen[offer.item] = offer.base end
    if entry.status ~= Market.READY and entry.status ~= Market.RAISED then return end
    if offer.kind == COMMODITY then
        C_AuctionHouse.StartCommoditiesPurchase(offer.item, offer.quantity, offer.unitPrice)
    else
        local auction = offer.auctions[1]
        C_AuctionHouse.PlaceBid(auction.auctionID, auction.buyoutAmount)
    end
    BeginPurchase(entry)
end

local PRICED = { ready = true, poor = true, raised = true }

function Market.Total()
    local cost = 0
    for _, entry in ipairs(entries) do
        local status = entry.status
        if status == Market.CONFIRM then
            cost = cost + entry.quotedTotal
        elseif PRICED[status] then
            cost = cost + entry.offer.cost
        end
    end
    return cost
end

local function OnPriceUpdated(_, totalPrice)
    local entry = buying
    if not entry or entry.offer.kind ~= COMMODITY then return end
    local offer = entry.offer
    entry.quotedTotal = totalPrice
    if totalPrice <= offer.quantity * offer.unitPrice then
        C_AuctionHouse.ConfirmCommoditiesPurchase(offer.item, offer.quantity)
        Changed()
        return
    end
    entry.status = Market.CONFIRM
    buying = nil
    CancelTimer(purchaseTimer)
    Changed()
end

local function PurchasingEntry()
    if buying then return buying end
    for _, entry in ipairs(entries) do
        if entry.status == Market.BUYING then return entry end
    end
end

local function OnPurchaseDone()
    local entry = PurchasingEntry()
    if entry then EndPurchase(entry, true) end
end

local function Bought(entry, quantity)
    Inventory.AddBought(entry.offer.item, quantity, entry.countBefore)
    EndPurchase(entry, true)
end

local function OnCommodityBought()
    local entry = PurchasingEntry()
    if entry then Bought(entry, entry.offer.quantity) end
end

local function OnItemPurchased(itemID)
    local offer = byItem[itemID]
    local entry = offer and offer.entry
    if entry and entry.status == Market.BUYING and entry.offer == offer and offer.kind == ITEM then
        Bought(entry, offer.auctions[1].quantity)
    end
end

local function Reset()
    CancelTimer(searchTimer)
    CancelTimer(purchaseTimer)
    if buying and buying.offer.kind == COMMODITY then C_AuctionHouse.CancelCommoditiesPurchase() end
    searching, buying = nil, nil
    wipe(queue)
    wipe(entries)
    wipe(byFamily)
    wipe(byItem)
    wipe(seen)
end

local function OnShow()
    if not ns.db.auction then return end
    Market.open = true
    Reset()
    Market.Rebuild()
    ns.Fire("MARKET_SHOWN", true)
end

local function OnClosed()
    if not Market.open then return end
    Market.open = false
    Reset()
    ns.Fire("MARKET_SHOWN", false)
end

local function Resettle()
    for _, entry in ipairs(entries) do
        Settle(entry)
    end
    Changed()
end

local REBUILD_SETTINGS = { stock = true, lowerRanks = true, countBank = true }

ns.Listen("INVENTORY_CHANGED", function()
    if Market.open then Market.Rebuild() end
end)
ns.Listen("FAMILIES_CHANGED", function()
    if Market.open then Market.Rebuild() end
end)
ns.Listen("SETTING_CHANGED", function(key)
    if not Market.open then return end
    if key == "auction" and not ns.db.auction then
        OnClosed()
    elseif key == nil or REBUILD_SETTINGS[key] then
        Market.Rebuild()
    elseif key == "priceStep" then
        Market.Refresh()
    end
end)

ns.Listen("LOGIN", function()
    ns.RegisterEvent("AUCTION_HOUSE_SHOW", OnShow)
    ns.RegisterEvent("AUCTION_HOUSE_CLOSED", OnClosed)
    ns.RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", Pump)
    ns.RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
        local offer = searching
        if not offer then return end
        searching = nil
        CancelTimer(searchTimer)
        offer.status = Market.QUEUED
        table.insert(queue, 1, offer)
    end)
    ns.RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommodityResults)
    ns.RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", OnItemResults)
    ns.RegisterEvent("COMMODITY_PRICE_UPDATED", OnPriceUpdated)
    ns.RegisterEvent("COMMODITY_PRICE_UNAVAILABLE", OnPurchaseDone)
    ns.RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", OnCommodityBought)
    ns.RegisterEvent("COMMODITY_PURCHASE_FAILED", OnPurchaseDone)
    ns.RegisterEvent("ITEM_PURCHASED", OnItemPurchased)
    ns.RegisterEvent("PLAYER_MONEY", Resettle)
end)
