local _, ns = ...

local NAME, MINOR = "LibJagerenteAuction", 1

local lib = _G[NAME]
if lib and lib.minor >= MINOR then
    ns.AuctionQueue = lib
    return
end

lib = lib or {}
lib.minor = MINOR
lib.queue = lib.queue or {}
lib.frame = lib.frame or CreateFrame("Frame")
_G[NAME] = lib
ns.AuctionQueue = lib

local SEARCH_TIMEOUT = 6
local SORTS = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }

local function StopActive()
    if lib.timer then lib.timer:Cancel() end
    lib.timer, lib.active = nil, nil
end

local function OnTimeout(request)
    if lib.active ~= request then return end
    StopActive()
    request.client.TimedOut(request.item)
    lib:Pump()
end

local function Send(request)
    lib.active = request
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(request.item), SORTS, false)
    if lib.active ~= request then return end
    lib.timer = C_Timer.NewTimer(SEARCH_TIMEOUT, function() OnTimeout(request) end)
end

function lib:Add(client, item)
    self.queue[#self.queue + 1] = { client = client, item = item }
end

function lib:Pump()
    if self.active then return end
    while #self.queue > 0 and C_AuctionHouse.IsThrottledMessageSystemReady() do
        local request = table.remove(self.queue, 1)
        if request.client.Begin(request.item) then
            Send(request)
            return
        end
    end
end

function lib:Done(client, item)
    local active = self.active
    if active and active.client == client and active.item == item then StopActive() end
    self:Pump()
end

function lib:Clear(client)
    local queue = self.queue
    for index = #queue, 1, -1 do
        if queue[index].client == client then table.remove(queue, index) end
    end
    if self.active and self.active.client == client then StopActive() end
end

local function RequeueActive()
    local active = lib.active
    if not active then return end
    StopActive()
    table.insert(lib.queue, 1, active)
end

local function OnEvent(_, event)
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        lib:Pump()
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        RequeueActive()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        StopActive()
        wipe(lib.queue)
    end
end

lib.frame:SetScript("OnEvent", OnEvent)
lib.frame:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
lib.frame:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
lib.frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
