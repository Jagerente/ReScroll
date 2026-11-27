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
local RESEARCH_DELAY = 0.5
local PERCENT = 100

local entries = Market.entries
local byFamily = {}
local byItem = {}
local shopping = {}
local keep = {}
local seen = {}
local asked = {}
local askedAll = false
local buying
local purchaseTimer
local windowOpen = false
local watchingEstimates = false
local PRICED = { ready = true, poor = true, raised = true }

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
    return entry.cooling or entry.status == Market.BUYING or entry.status == Market.CONFIRM
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

local function BeginSearch(item)
    local offer = byItem[item]
    if not offer or Market.IsSettled(offer) then return false end
    offer.status = Market.SEARCHING
    Changed()
    return true
end

local function SearchTimedOut(item)
    local offer = byItem[item]
    if not offer or offer.status ~= Market.SEARCHING then return end
    offer.status = Market.NONE
    Settle(offer.entry)
    Changed()
end

local searcher = { Begin = BeginSearch, TimedOut = SearchTimedOut }

local function Enqueue(offer)
    if not Market.IsSettled(offer) then return end
    offer.status = Market.QUEUED
    ns.AuctionQueue:Add(searcher, offer.item)
end

local function Research(entry)
    for _, offer in ipairs(entry.offers) do
        if entry.priced then
            Enqueue(offer)
        else
            offer.status = Market.IDLE
        end
    end
    Settle(entry)
end

local function FinishSearch(offer)
    Settle(offer.entry)
    Changed()
    ns.AuctionQueue:Done(searcher, offer.item)
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
    if not offer then return false end
    local entry = offer.entry
    return not (Market.Busy(entry) and entry.offer == offer)
end

local function OnCommodityResults(itemID)
    local offer = byItem[itemID]
    if not Accepts(offer) then
        ns.AuctionQueue:Done(searcher, itemID)
        return
    end
    ReadCommodities(offer)
    FinishSearch(offer)
end

local function OnItemResults(itemKey)
    local item = itemKey and itemKey.itemID
    local offer = item and byItem[item]
    if not Accepts(offer) then
        ns.AuctionQueue:Done(searcher, item)
        return
    end
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
    if not stale or Market.Busy(entry) then return end
    if not sameRanks then SetRanks(entry, wanted) end
    Research(entry)
end

local function Rebuild()
    Inventory.GetShoppingList(shopping)
    wipe(entries)
    wipe(keep)
    for _, wanted in ipairs(shopping) do
        local key = wanted.family.key
        local entry = byFamily[key]
        if not entry then
            entry = { family = wanted.family, offers = {}, priced = askedAll or asked[key] }
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
    ns.AuctionQueue:Pump()
end

local function HasResult(entry)
    return entry.priced or PRICED[entry.status] or entry.status == Market.NONE
end

local function HasPrice(entry)
    return HasResult(entry) or entry.status == Market.ESTIMATED
end

local function MarkPriced(entry)
    asked[entry.family.key] = true
    entry.priced = true
end

local function DropQuote(entry)
    if entry.status ~= Market.CONFIRM then return end
    C_AuctionHouse.CancelCommoditiesPurchase()
    entry.status = Market.IDLE
end

function Market.Refresh()
    for _, entry in ipairs(entries) do
        DropQuote(entry)
        if HasPrice(entry) and not Market.Busy(entry) then
            MarkPriced(entry)
            Research(entry)
        end
    end
    Changed()
    ns.AuctionQueue:Pump()
end

local function RequestPrices(entry)
    if entry.priced or Market.Busy(entry) then return end
    MarkPriced(entry)
    Research(entry)
end

function Market.FindPrices(entry)
    if entry then
        RequestPrices(entry)
    else
        askedAll = true
        for _, each in ipairs(entries) do RequestPrices(each) end
    end
    Changed()
    ns.AuctionQueue:Pump()
end

function Market.PriceCounts()
    local waiting, known = 0, 0
    for _, entry in ipairs(entries) do
        if HasPrice(entry) then known = known + 1 else waiting = waiting + 1 end
    end
    return waiting, known
end

function Market.EstimatedCost(entry)
    local offer = entry.offer
    local status = entry.status
    if entry.cooling or not offer or not offer.estimate then return nil end
    if status ~= Market.IDLE and status ~= Market.SEARCHING and status ~= Market.ESTIMATED then return nil end
    return offer.estimate * entry.need
end

function Market.Pick(entry, rank)
    local offer = byItem[rank.item]
    if Market.Busy(entry) or not offer or not Market.IsAvailable(offer) then return end
    local default = entry.offers[1].rank == rank
    ns.charDB.buyRanks[entry.family.key] = not default and rank.index or nil
    Settle(entry)
    ns.Fire("STOCK_CHANGED")
    if entry.status == Market.ESTIMATED then
        Changed()
    else
        Market.FindPrices(entry)
    end
end

local function FinishCooling(entry)
    if byFamily[entry.family.key] ~= entry then return end
    entry.cooling = nil
    Rebuild()
    if byFamily[entry.family.key] == entry then Research(entry) end
    Changed()
    ns.AuctionQueue:Pump()
end

local function EndPurchase(entry)
    CancelTimer(purchaseTimer)
    if buying == entry then buying = nil end
    entry.status = Market.SEARCHING
    entry.cooling = true
    C_Timer.After(RESEARCH_DELAY, function() FinishCooling(entry) end)
    Changed()
end

local function StartPurchaseTimer(entry)
    CancelTimer(purchaseTimer)
    purchaseTimer = C_Timer.NewTimer(PURCHASE_TIMEOUT, function()
        if buying == entry then EndPurchase(entry) end
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
    local status = entry.status
    if status == Market.RAISED then seen[offer.item] = offer.base end
    if status ~= Market.READY and status ~= Market.RAISED and status ~= Market.ESTIMATED then return end
    MarkPriced(entry)
    if status == Market.ESTIMATED then
        offer.kind, offer.quantity = COMMODITY, entry.need
        entry.limit = Ceiling(offer.estimate) * offer.quantity
        C_AuctionHouse.StartCommoditiesPurchase(offer.item, offer.quantity)
    elseif offer.kind == COMMODITY then
        entry.limit = offer.quantity * offer.unitPrice
        C_AuctionHouse.StartCommoditiesPurchase(offer.item, offer.quantity)
    else
        local auction = offer.auctions[1]
        C_AuctionHouse.PlaceBid(auction.auctionID, auction.buyoutAmount)
    end
    BeginPurchase(entry)
end

function Market.Total()
    local cost, approximate = 0, false
    for _, entry in ipairs(entries) do
        local status = entry.status
        if status == Market.CONFIRM then
            cost = cost + entry.quotedTotal
        elseif PRICED[status] then
            cost = cost + entry.offer.cost
        else
            local estimate = Market.EstimatedCost(entry)
            if estimate then cost, approximate = cost + estimate, true end
        end
    end
    return cost, approximate
end

local function OnPriceUpdated(_, totalPrice)
    local entry = buying
    if not entry or entry.offer.kind ~= COMMODITY then return end
    local offer = entry.offer
    entry.quotedTotal = totalPrice
    if totalPrice <= entry.limit then
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
    if entry then EndPurchase(entry) end
end

local function Bought(entry, quantity)
    Inventory.AddBought(entry.offer.item, quantity, entry.countBefore)
    EndPurchase(entry)
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
    ns.AuctionQueue:Clear(searcher)
    CancelTimer(purchaseTimer)
    if buying and buying.offer.kind == COMMODITY then C_AuctionHouse.CancelCommoditiesPurchase() end
    buying = nil
    askedAll = false
    wipe(asked)
    wipe(entries)
    wipe(byFamily)
    wipe(byItem)
    wipe(seen)
end

local function RefreshEstimates()
    if not Market.open then return end
    for item, offer in pairs(byItem) do
        offer.estimate = Estimate(item)
        if offer.estimate and offer.commodity == nil then offer.commodity = IsCommodity(item) end
    end
    for _, entry in ipairs(entries) do
        Settle(entry)
    end
    Changed()
end

local function OnItemKeyInfo(item)
    local offer = byItem[item]
    if not offer or not offer.estimate or offer.commodity ~= nil then return end
    offer.commodity = IsCommodity(item)
    Settle(offer.entry)
    Changed()
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

local function Resettle()
    for _, entry in ipairs(entries) do
        Settle(entry)
    end
    Changed()
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
        Market.Refresh()
    end
end)

ns.Listen("LOGIN", function()
    ns.RegisterEvent("AUCTION_HOUSE_SHOW", OnShow)
    ns.RegisterEvent("AUCTION_HOUSE_CLOSED", OnClosed)
    ns.RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommodityResults)
    ns.RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", OnItemResults)
    ns.RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED", OnItemKeyInfo)
    ns.RegisterEvent("COMMODITY_PRICE_UPDATED", OnPriceUpdated)
    ns.RegisterEvent("COMMODITY_PRICE_UNAVAILABLE", OnPurchaseDone)
    ns.RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", OnCommodityBought)
    ns.RegisterEvent("COMMODITY_PURCHASE_FAILED", OnPurchaseDone)
    ns.RegisterEvent("ITEM_PURCHASED", OnItemPurchased)
    ns.RegisterEvent("PLAYER_MONEY", Resettle)
    ns.RegisterEvent("PLAYER_LEVEL_UP", OnLevelUp)
end)
