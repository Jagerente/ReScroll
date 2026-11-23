local _, ns = ...

local Inventory = ns.Inventory
local Catalog = ns.Catalog

local Bank = { open = false, entries = {}, moving = false, noSpace = false }
ns.Bank = Bank

local OPEN_DELAY = 0.3
local STEP_DELAY = 0.3
local LOCK_RETRY = 0.2
local MAX_LOCK_WAITS = 15
local GENERIC_BAG = 0
local BANK_TYPES = { Enum.BankType.Character, Enum.BankType.Account }

local entries = Bank.entries
local pool = {}
local ranks = {}
local job
local lastMove
local lockWaits = 0
local windowOpen = false
local takeOnOpen = false

local function Changed()
    ns.Fire("BANK_CHANGED")
end

local function FindInBank(item)
    for _, bankType in ipairs(BANK_TYPES) do
        if C_Bank.CanViewBank(bankType) then
            for _, tab in ipairs(C_Bank.FetchPurchasedBankTabIDs(bankType)) do
                for slot = 1, C_Container.GetContainerNumSlots(tab) do
                    local info = C_Container.GetContainerItemInfo(tab, slot)
                    if info and info.itemID == item and not info.isLocked then return tab, slot, info.stackCount end
                end
            end
        end
    end
end

local function FindRoom(item, count)
    local maxStack = C_Item.GetItemMaxStackSizeByID(item) or 1
    local emptyBag, emptySlot
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.Bag_4 do
        local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
        local plain = bagFamily == nil or bagFamily == GENERIC_BAG
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                if info.itemID == item and not info.isLocked and info.stackCount + count <= maxStack then return bag, slot end
            elseif plain and not emptyBag then
                emptyBag, emptySlot = bag, slot
            end
        end
    end
    return emptyBag, emptySlot
end

function Bank.FreeSlots()
    local free = 0
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.Bag_4 do
        local count, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
        if bagFamily == nil or bagFamily == GENERIC_BAG then free = free + count end
    end
    return free
end

local function BestRankInBank(family, level, grade)
    for _, rank in ipairs(Inventory.CountedRanks(family, level, grade, ranks)) do
        if Inventory.BankCount(rank.item) > 0 then return rank end
    end
end

local function Rebuild()
    wipe(entries)
    local level = UnitLevel("player")
    for _, family in ipairs(Catalog.restocked) do
        if Inventory.Restockable(family, level) then
            local grade = Inventory.StockRank(family, level)
            local have, inBank = Inventory.StockCount(family, grade)
            local take = math.min(Inventory.StockTarget(family) - have, inBank)
            if take > 0 then
                local entry = pool[family.key] or { family = family }
                pool[family.key] = entry
                entry.take, entry.have, entry.bank, entry.grade = take, have, inBank, grade
                entry.rank = BestRankInBank(family, level, entry.grade)
                entries[#entries + 1] = entry
            end
        end
    end
end

local function NextMove()
    local level = UnitLevel("player")
    for _, entry in ipairs(entries) do
        if not job.key or job.key == entry.family.key then
            for _, rank in ipairs(Inventory.CountedRanks(entry.family, level, entry.grade, ranks)) do
                local bag, slot, stack = FindInBank(rank.item)
                if bag then
                    return { item = rank.item, bag = bag, slot = slot, stack = stack, count = math.min(entry.take, stack) }
                end
            end
        end
    end
end

local function Locked(move)
    local source = C_Container.GetContainerItemInfo(move.bag, move.slot)
    local target = C_Container.GetContainerItemInfo(move.toBag, move.toSlot)
    return (source ~= nil and source.isLocked) or (target ~= nil and target.isLocked)
end

local function Finish()
    job, lastMove = nil, nil
    Bank.moving = false
    Rebuild()
    Changed()
end

local Step

local function Move(move)
    if move.count < move.stack then
        C_Container.SplitContainerItem(move.bag, move.slot, move.count)
    else
        C_Container.PickupContainerItem(move.bag, move.slot)
    end
    C_Container.PickupContainerItem(move.toBag, move.toSlot)
    lastMove, lockWaits = move, 0
    Bank.moving = true
    Changed()
    ns.Schedule("bankStep", STEP_DELAY, Step)
end

function Step()
    if not job or not Bank.open then return Finish() end
    if lastMove and Locked(lastMove) then
        lockWaits = lockWaits + 1
        if lockWaits > MAX_LOCK_WAITS then return Finish() end
        return ns.Schedule("bankStep", LOCK_RETRY, Step)
    end
    if CursorHasItem() then return Finish() end
    Inventory.Recount()
    Rebuild()
    local move = NextMove()
    if not move then return Finish() end
    move.toBag, move.toSlot = FindRoom(move.item, move.count)
    if not move.toBag then
        Bank.noSpace = true
        return Finish()
    end
    Move(move)
end

function Bank.Take(entry)
    if not Bank.open or job then return end
    job = { key = entry and entry.family.key }
    Bank.noSpace = false
    Step()
end

local function ShowPanel(runAuto)
    Bank.open = true
    Bank.noSpace = false
    takeOnOpen = takeOnOpen or runAuto
    ns.Schedule("bankOpen", OPEN_DELAY, function()
        local take = takeOnOpen
        takeOnOpen = false
        if not Bank.open then return end
        Inventory.Recount()
        Rebuild()
        if #entries == 0 then return end
        ns.Fire("BANK_SHOWN", true)
        if take and ns.db.bankAuto then Bank.Take() end
    end)
end

local function HidePanel()
    if not Bank.open then return end
    Bank.open = false
    job, lastMove = nil, nil
    Bank.moving = false
    ns.Fire("BANK_SHOWN", false)
end

local function OnOpened()
    windowOpen = true
    if ns.db.bank then ShowPanel(true) end
end

local function OnClosed()
    windowOpen = false
    takeOnOpen = false
    HidePanel()
end

local function SyncPanel()
    if not ns.db.bank then
        HidePanel()
    elseif windowOpen and not Bank.open then
        ShowPanel(false)
    end
end

local function RebuildIfIdle()
    if not Bank.open or job then return end
    Rebuild()
    Changed()
end

ns.Listen("INVENTORY_CHANGED", RebuildIfIdle)
ns.Listen("FAMILIES_CHANGED", RebuildIfIdle)
ns.Listen("STOCK_CHANGED", RebuildIfIdle)
ns.Listen("SETTING_CHANGED", function(key)
    if key == nil or key == "bank" then SyncPanel() end
    RebuildIfIdle()
end)

ns.Listen("LOGIN", function()
    ns.RegisterEvent("BANKFRAME_OPENED", OnOpened)
    ns.RegisterEvent("BANKFRAME_CLOSED", OnClosed)
end)
