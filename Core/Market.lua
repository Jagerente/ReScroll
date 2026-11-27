local _, ns = ...

local Inventory = ns.Inventory

local Market = { open = false, entries = {} }
ns.Market = Market

Market.IDLE = "idle"
Market.QUEUED = "queued"
Market.SEARCHING = "searching"
Market.READY = "ready"
Market.NONE = "none"
Market.BUYING = "buying"
Market.CONFIRM = "confirm"
Market.POOR = "poor"
Market.RAISED = "raised"
Market.ENOUGH = "enough"
Market.ESTIMATED = "estimated"

local COMMODITY, ITEM = "commodity", "item"
local PURCHASE_TIMEOUT = 10
local PERCENT = 100
local PRICED = { ready = true, poor = true, raised = true }

local entries = Market.entries
local byFamily = {}
local byItem = {}
local shopping = {}
local keep = {}
local found = {}
local pending = {}
local seen = {}
local buying
local purchaseTimer
local windowOpen = false
local watchingEstimates = false

local function Changed()
    ns.Fire("MARKET_CHANGED")
end

local function CancelTimer(timer)
    if timer then timer:Cancel() end
end

local function AuctionatorAPI()
    local auctionator = Auctionator
    return auctionator and auctionator.API and auctionator.API.v1
end

local function Estimate(item)
    local api = AuctionatorAPI()
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local price = api.GetAuctionPriceByItemID(ns.ADDON, item)
    return type(price) == "number" and price > 0 and price or nil
end

local function IsCommodity(item)
    local info = C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(item))
    if info then return info.isCommodity end
end

local function BuysAtEstimate(offer)
    return offer.estimate ~= nil and offer.commodity == true
end

function Market.Busy(entry)
    return entry.status == Market.BUYING or entry.status == Market.CONFIRM
end

local function Ceiling(base)
    return base * (1 + ns.db.priceStep / PERCENT)
end

function Market.IsSettled(offer)
    return offer.status ~= Market.QUEUED and offer.status ~= Market.SEARCHING
end

function Market.IsAvailable(offer)
    return offer.status == Market.READY or offer.status == Market.IDLE or not Market.IsSettled(offer)
end

local function ChosenOffer(entry)
    local index = ns.charDB.buyRanks[entry.family.key]
    for _, offer in ipairs(entry.offers) do
        if offer.rank.index == index and Market.IsAvailable(offer) then return offer end
    end
    for _, offer in ipairs(entry.offers) do
        if Market.IsAvailable(offer) then return offer end
    end
end

function Market.SeenPrice(item)
    return seen[item]
end

function Market.IsRaised(offer)
    local first = seen[offer.item]
    return first ~= nil and offer.base > Ceiling(first)
end

local function Unknown(offer)
    return offer.estimate == nil and found[offer.item] == nil and pending[offer.item] == nil
end

local function SetPrice(offer, quantity, cost, base, beyond)
    offer.quantity, offer.cost = quantity, cost
    offer.unitCost = quantity > 0 and cost / quantity or base or 0
    offer.base, offer.beyond = base or 0, beyond
    offer.status = base and Market.READY or Market.NONE
end

local function PriceCommodity(offer, lots)
    local need, base = offer.need, lots[1] and lots[1].unitPrice
    local quantity, cost, beyond = 0, 0, nil
    for _, lot in ipairs(lots) do
        if quantity >= need then break end
        if lot.unitPrice > Ceiling(base) then
            beyond = lot.unitPrice
            break
        end
        local take = math.min(need - quantity, lot.quantity)
        quantity = quantity + take
        cost = cost + take * lot.unitPrice
    end
    offer.kind = COMMODITY
    SetPrice(offer, quantity, cost, base, beyond)
    offer.nextCost = cost
    offer.unitPrice = quantity > 0 and math.ceil(cost / quantity) or 0
end

local function UnitPrice(lot)
    return lot.buyoutAmount / lot.quantity
end

local function ByUnitPrice(a, b)
    return UnitPrice(a) < UnitPrice(b)
end

local function PriceItems(offer, lots)
    local need, base = offer.need, lots[1] and UnitPrice(lots[1])
    local auctions = offer.auctions or {}
    wipe(auctions)
    local quantity, cost, beyond = 0, 0, nil
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
    SetPrice(offer, quantity, cost, base, beyond)
    offer.nextCost = auctions[1] and auctions[1].buyoutAmount or 0
end

local function Price(offer)
    local item = offer.item
    local result = found[item]
    if pending[item] then
        offer.status = pending[item]
    elseif not result then
        offer.status = Market.IDLE
    elseif result.kind == ITEM then
        PriceItems(offer, result.lots)
    else
        PriceCommodity(offer, result.lots)
    end
end

local function ShowStock(entry, offer)
    local source = offer or entry.offers[1]
    entry.need, entry.have, entry.bank, entry.mail = source.need, source.have, source.bank, source.mail
end

local function Settle(entry)
    if Market.Busy(entry) then return end
    local offer = ChosenOffer(entry)
    entry.offer = offer
    ShowStock(entry, offer)
    if not offer then
        entry.status = Market.NONE
    elseif not Market.IsSettled(offer) then
        entry.status = Market.SEARCHING
    elseif offer.need <= 0 then
        entry.status = Market.ENOUGH
    elseif offer.status == Market.IDLE then
        entry.status = BuysAtEstimate(offer) and Market.ESTIMATED or Market.IDLE
    elseif offer.nextCost > GetMoney() then
        entry.status = Market.POOR
    elseif Market.IsRaised(offer) then
        entry.status = Market.RAISED
    else
        entry.status = Market.READY
    end
end

local function Reprice()
    for _, entry in ipairs(entries) do
        for _, offer in ipairs(entry.offers) do
            Price(offer)
        end
        Settle(entry)
    end
    Changed()
end

local function BeginSearch(item)
    if not pending[item] or not byItem[item] then
        pending[item] = nil
        return false
    end
    pending[item] = Market.SEARCHING
    Reprice()
    return true
end

local function SearchTimedOut(item)
    if pending[item] ~= Market.SEARCHING then return end
    pending[item] = nil
    found[item] = { lots = {} }
    Reprice()
end

local searcher = { Begin = BeginSearch, TimedOut = SearchTimedOut }

local function Request(item, again)
    if pending[item] or (found[item] and not again) then return end
    pending[item] = Market.QUEUED
    ns.AuctionQueue:Add(searcher, item)
end

local function InPurchase(item)
    for _, entry in ipairs(entries) do
        if entry.purchase and entry.purchase.item == item then return true end
    end
    return buying ~= nil and buying.purchase.item == item
end

local function Wanted(item)
    return item ~= nil and (byItem[item] ~= nil or pending[item] ~= nil) and not InPurchase(item)
end

local function Store(item, kind, lots)
    pending[item] = nil
    found[item] = { kind = kind, lots = lots }
    local first = lots[1]
    if first and not seen[item] then seen[item] = kind == ITEM and UnitPrice(first) or first.unitPrice end
    Reprice()
end

local function ReadCommodityLots(item)
    local lots = {}
    for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(item) do
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(item, index)
        local available = result and result.quantity - result.numOwnerItems or 0
        if available > 0 then lots[#lots + 1] = { unitPrice = result.unitPrice, quantity = available } end
    end
    return lots
end

local function ReadItemLots(itemKey)
    local lots = {}
    for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
        if result and result.buyoutAmount and not result.containsOwnerItem then
            lots[#lots + 1] = { auctionID = result.auctionID, quantity = result.quantity, buyoutAmount = result.buyoutAmount }
        end
    end
    table.sort(lots, ByUnitPrice)
    return lots
end

local function OnCommodityResults(item)
    if Wanted(item) then Store(item, COMMODITY, ReadCommodityLots(item)) end
    ns.AuctionQueue:Done(searcher, item)
end

local function OnItemResults(itemKey)
    local item = itemKey and itemKey.itemID
    if Wanted(item) then Store(item, ITEM, ReadItemLots(itemKey)) end
    ns.AuctionQueue:Done(searcher, item)
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
    offer.need, offer.have, offer.bank, offer.mail = stock.need, stock.have, stock.bank, stock.mail
end

local function SetRanks(entry, wanted)
    DropOffers(entry)
    for index, rank in ipairs(wanted.ranks) do
        local estimate = Estimate(rank.item)
        local offer = {
            entry = entry, rank = rank, item = rank.item,
            estimate = estimate, commodity = estimate and IsCommodity(rank.item),
        }
        CopyStock(offer, wanted.stocks[index])
        entry.offers[index] = offer
        byItem[rank.item] = offer
    end
end

local function Restock(entry, wanted)
    for index, offer in ipairs(entry.offers) do
        CopyStock(offer, wanted.stocks[index])
    end
end

local function Sync(entry, wanted)
    if Market.Busy(entry) then return end
    if SameRanks(entry, wanted.ranks) then
        Restock(entry, wanted)
    else
        SetRanks(entry, wanted)
    end
end

local function Rebuild()
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
    Reprice()
    ns.AuctionQueue:Pump()
end

local function DropQuote(entry)
    if entry.status ~= Market.CONFIRM then return end
    C_AuctionHouse.CancelCommoditiesPurchase()
    entry.purchase = nil
    entry.status = Market.IDLE
end

local function RefreshEntry(entry, only)
    if entry.status == Market.BUYING then return end
    local purchase = entry.purchase
    if not only or (purchase and purchase.item == only.item) then DropQuote(entry) end
    for _, offer in ipairs(entry.offers) do
        if not only or offer == only then Request(offer.item, true) end
    end
end

function Market.Refresh(entry, offer)
    if entry then
        RefreshEntry(entry, offer)
    else
        for _, each in ipairs(entries) do RefreshEntry(each) end
    end
    Reprice()
    ns.AuctionQueue:Pump()
end

local function FindEntry(entry)
    if Market.Busy(entry) then return end
    for _, offer in ipairs(entry.offers) do
        if offer == entry.offer or Unknown(offer) then Request(offer.item) end
    end
end

function Market.FindPrices(entry)
    if entry then
        FindEntry(entry)
    else
        for _, each in ipairs(entries) do
            if each.status == Market.IDLE then FindEntry(each) end
        end
    end
    Reprice()
    ns.AuctionQueue:Pump()
end

local function ShowsPrice(entry)
    for _, offer in ipairs(entry.offers) do
        if offer.estimate or found[offer.item] or pending[offer.item] then return true end
    end
    return false
end

function Market.PriceCounts()
    local waiting, known = 0, 0
    for _, entry in ipairs(entries) do
        if entry.status == Market.IDLE then waiting = waiting + 1 end
        if ShowsPrice(entry) then known = known + 1 end
    end
    return waiting, known
end

function Market.EstimatedCost(entry)
    local offer = entry.offer
    local status = entry.status
    if not offer or not offer.estimate then return nil end
    if status ~= Market.IDLE and status ~= Market.SEARCHING and status ~= Market.ESTIMATED then return nil end
    return offer.estimate * entry.need
end

function Market.Pick(entry, rank)
    local offer = byItem[rank.item]
    if Market.Busy(entry) or not offer or not Market.IsAvailable(offer) then return end
    local default = entry.offers[1].rank == rank
    ns.charDB.buyRanks[entry.family.key] = not default and rank.index or nil
    ns.Fire("STOCK_CHANGED")
    if Unknown(offer) then Request(offer.item) end
    Rebuild()
end

local function EndPurchase(entry)
    CancelTimer(purchaseTimer)
    if buying == entry then buying = nil end
    entry.purchase = nil
    entry.status = Market.IDLE
end

local function Failed(entry)
    local item = entry.purchase.item
    EndPurchase(entry)
    Request(item, true)
    Rebuild()
end

local function BeginPurchase(entry, purchase)
    buying = entry
    entry.purchase = purchase
    entry.status = Market.BUYING
    entry.countBefore = Inventory.TotalCount(purchase.item)
    CancelTimer(purchaseTimer)
    purchaseTimer = C_Timer.NewTimer(PURCHASE_TIMEOUT, function()
        if buying == entry then Failed(entry) end
    end)
    Changed()
end

local function BuyCommodity(entry, item, quantity, limit)
    C_AuctionHouse.StartCommoditiesPurchase(item, quantity)
    BeginPurchase(entry, { kind = COMMODITY, item = item, quantity = quantity, limit = limit })
end

function Market.Buy(entry)
    if buying or not entry then return end
    local status, offer = entry.status, entry.offer
    if status == Market.CONFIRM then
        local purchase = entry.purchase
        C_AuctionHouse.ConfirmCommoditiesPurchase(purchase.item, purchase.quantity)
        BeginPurchase(entry, purchase)
        return
    end
    if status == Market.ESTIMATED then
        BuyCommodity(entry, offer.item, entry.need, Ceiling(offer.estimate) * entry.need)
        return
    end
    if status ~= Market.READY and status ~= Market.RAISED then return end
    if status == Market.RAISED then seen[offer.item] = offer.base end
    if offer.kind == COMMODITY then
        BuyCommodity(entry, offer.item, offer.quantity, offer.quantity * offer.unitPrice)
        return
    end
    local auction = offer.auctions[1]
    C_AuctionHouse.PlaceBid(auction.auctionID, auction.buyoutAmount)
    BeginPurchase(entry, { kind = ITEM, item = offer.item, quantity = auction.quantity, auction = auction.auctionID })
end

function Market.Total()
    local cost, approximate, counted = 0, false, 0
    for _, entry in ipairs(entries) do
        local status = entry.status
        local estimate = Market.EstimatedCost(entry)
        if status == Market.CONFIRM then
            cost, counted = cost + entry.quotedTotal, counted + 1
        elseif PRICED[status] then
            cost, counted = cost + entry.offer.cost, counted + 1
        elseif estimate then
            cost, counted, approximate = cost + estimate, counted + 1, true
        end
    end
    return cost, approximate, counted
end

local function OnPriceUpdated(_, totalPrice)
    local entry = buying
    local purchase = entry and entry.purchase
    if not purchase or purchase.kind ~= COMMODITY then return end
    entry.quotedTotal = totalPrice
    if totalPrice <= purchase.limit then
        C_AuctionHouse.ConfirmCommoditiesPurchase(purchase.item, purchase.quantity)
        return
    end
    CancelTimer(purchaseTimer)
    buying = nil
    entry.status = Market.CONFIRM
    Changed()
end

local function TakeAuction(lots, auctionID)
    for index, lot in ipairs(lots) do
        if lot.auctionID == auctionID then
            table.remove(lots, index)
            return
        end
    end
end

local function TakeUnits(lots, quantity)
    local left = quantity
    while left > 0 and lots[1] do
        local lot = lots[1]
        local take = math.min(left, lot.quantity)
        lot.quantity, left = lot.quantity - take, left - take
        if lot.quantity == 0 then table.remove(lots, 1) end
    end
end

local function Bought(entry)
    local purchase = entry.purchase
    local result = found[purchase.item]
    if result and purchase.auction then
        TakeAuction(result.lots, purchase.auction)
    elseif result then
        TakeUnits(result.lots, purchase.quantity)
    end
    EndPurchase(entry)
    Inventory.AddBought(purchase.item, purchase.quantity, entry.countBefore)
    Rebuild()
end

local function OnPurchaseFailed()
    if buying then Failed(buying) end
end

local function OnCommodityBought()
    local purchase = buying and buying.purchase
    if purchase and purchase.kind == COMMODITY then Bought(buying) end
end

local function OnItemPurchased(itemID)
    local purchase = buying and buying.purchase
    if purchase and purchase.kind == ITEM and purchase.item == itemID then Bought(buying) end
end

local function Reset()
    ns.AuctionQueue:Clear(searcher)
    CancelTimer(purchaseTimer)
    if buying and buying.purchase.kind == COMMODITY then C_AuctionHouse.CancelCommoditiesPurchase() end
    buying = nil
    wipe(entries)
    wipe(byFamily)
    wipe(byItem)
    wipe(found)
    wipe(pending)
    wipe(seen)
end

local function RefreshEstimates()
    if not Market.open then return end
    for item, offer in pairs(byItem) do
        offer.estimate = Estimate(item)
        if offer.estimate and offer.commodity == nil then offer.commodity = IsCommodity(item) end
    end
    Reprice()
end

local function OnItemKeyInfo(item)
    local offer = byItem[item]
    if not offer or not offer.estimate or offer.commodity ~= nil then return end
    offer.commodity = IsCommodity(item)
    Reprice()
end

local function WatchEstimates()
    if watchingEstimates then return end
    local api = AuctionatorAPI()
    if not (api and api.RegisterForDBUpdate) then return end
    watchingEstimates = true
    api.RegisterForDBUpdate(ns.ADDON, function() ns.Schedule("marketEstimates", 0, RefreshEstimates) end)
end

local function ShowPanel()
    Market.open = true
    WatchEstimates()
    Reset()
    Rebuild()
    ns.Fire("MARKET_SHOWN", true)
end

local function HidePanel()
    if not Market.open then return end
    Market.open = false
    Reset()
    ns.Fire("MARKET_SHOWN", false)
end

local function OnShow()
    windowOpen = true
    if ns.db.auction then ShowPanel() end
end

local function OnClosed()
    windowOpen = false
    HidePanel()
end

local function SyncPanel()
    if not ns.db.auction then
        HidePanel()
        ns.AuctionQueue:Pump()
    elseif windowOpen and not Market.open then
        ShowPanel()
    end
end

local function RepriceIfOpen()
    if Market.open then Reprice() end
end

local REBUILD_SETTINGS = { lowerRanks = true, countBank = true }

local function RebuildIfOpen()
    if Market.open then Rebuild() end
end

local function OnLevelUp()
    ns.Schedule("marketLevel", 0, RebuildIfOpen)
end

ns.Listen("INVENTORY_CHANGED", RebuildIfOpen)
ns.Listen("FAMILIES_CHANGED", RebuildIfOpen)
ns.Listen("STOCK_CHANGED", RebuildIfOpen)
ns.Listen("SETTING_CHANGED", function(key)
    if key == nil or key == "auction" then SyncPanel() end
    if not Market.open then return end
    if key == nil or REBUILD_SETTINGS[key] then
        Rebuild()
    elseif key == "priceStep" then
        Reprice()
    end
end)

ns.Listen("LOGIN", function()
    ns.RegisterEvent("AUCTION_HOUSE_SHOW", OnShow)
    ns.RegisterEvent("AUCTION_HOUSE_CLOSED", OnClosed)
    ns.RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommodityResults)
    ns.RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", OnItemResults)
    ns.RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED", OnItemKeyInfo)
    ns.RegisterEvent("COMMODITY_PRICE_UPDATED", OnPriceUpdated)
    ns.RegisterEvent("COMMODITY_PRICE_UNAVAILABLE", OnPurchaseFailed)
    ns.RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", OnCommodityBought)
    ns.RegisterEvent("COMMODITY_PURCHASE_FAILED", OnPurchaseFailed)
    ns.RegisterEvent("ITEM_PURCHASED", OnItemPurchased)
    ns.RegisterEvent("PLAYER_MONEY", RepriceIfOpen)
    ns.RegisterEvent("PLAYER_LEVEL_UP", OnLevelUp)
end)
