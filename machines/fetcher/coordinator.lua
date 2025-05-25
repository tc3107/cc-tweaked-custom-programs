-- coordinator.lua
-- Central Server: discovers indexers dynamically, partitions inventories between
-- them, aggregates their results and replies to clients with a global index.

local NETWORK_PROTOCOL   = "inventoryNet"
local DISCOVERY_ACTION   = "discover_indexers"
local DISCOVERY_REPLY    = "discover_response"
local TIMEOUT_SEC        = 60

-- Count number of keys in a table
local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Discover all chests on the network
local function findChests()
  local chests = {}
  for _, name in ipairs(peripheral.getNames()) do
    local ok, per = pcall(peripheral.wrap, name)
    if ok and type(per.list)=="function" then
      table.insert(chests, name)
    end
  end
  return chests
end

-- Partition a list into N roughly equal chunks
local function partition(list, N)
  local chunks = {}
  local count = #list
  local size = math.ceil(count / N)
  for i=1,N do
    local start = (i-1)*size + 1
    local stop = math.min(i*size, count)
    chunks[i] = {}
    for j=start,stop do chunks[i][#chunks[i]+1] = list[j] end
  end
  return chunks
end

-- Convert indexer results (per-chest) into a global item index
local function buildGlobalIndex(results)
  local merged = {}
  for _, chestData in pairs(results) do
    for chest, slots in pairs(chestData) do
      for slot, item in pairs(slots) do
        if item and item.name then
          if not merged[item.name] then
            merged[item.name] = { total = 0, sources = {} }
          end
          merged[item.name].total = merged[item.name].total + item.count
          table.insert(merged[item.name].sources, {
            chest = chest,
            slot  = slot,
            count = item.count
          })
        end
      end
    end
  end
  return merged
end


-- Initialize rednet
local function initRednet()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name):match("modem") then
      rednet.open(name)
      return true
    end
  end
  return false
end

-- MAIN
if not initRednet() then
  error("No modem found")
end

-- Discover indexers by broadcasting and waiting for replies
local function discoverIndexers(reqId)
  local ids = {}
  rednet.broadcast({{ action = DISCOVERY_ACTION, requestId = reqId }}, NETWORK_PROTOCOL)
  local timer = os.startTimer(3)
  while true do
    local event, p1, p2, p3 = os.pullEvent()
    if event == "rednet_message" then
      local from, msg, proto = p1, p2, p3
      local data = type(msg) == "table" and msg[1]
      if proto == NETWORK_PROTOCOL and type(data) == "table" and data.action == DISCOVERY_REPLY and data.requestId == reqId then
        ids[#ids + 1] = from
      end
    elseif event == "timer" and p1 == timer then
      break
    end
  end
  return ids
end

print("Coordinator ready. Waiting for client requests...")

local requestCounter = 0

while true do
  local sender, msg = rednet.receive(NETWORK_PROTOCOL)
  local data = type(msg)=="table" and msg[1]
  if sender and type(msg)=="table" and type(data)=="table" and data.action=="index_request" then
    requestCounter = requestCounter + 1
    local reqId = requestCounter
    print(("Index request #%d from %d"):format(reqId, sender))

    -- discover chests and indexers
    local allChests = findChests()
    print(string.format("Found %d inventories on network", #allChests))
    local indexers = discoverIndexers(reqId)
    print(string.format("Discovered %d indexer(s)", #indexers))
    if #indexers == 0 then
      rednet.send(sender, {{ action = "index_response", requestId = reqId, data = {} }}, NETWORK_PROTOCOL)
      print("No indexers available. Sent empty index.")
      goto continue
    end

    local chunks = partition(allChests, #indexers)

    -- dispatch to indexers
    for i, idxId in ipairs(indexers) do
      local payload = {
        action    = "index",
        requestId = reqId,
        chests    = chunks[i]
      }
      rednet.send(idxId, {payload}, NETWORK_PROTOCOL)
    end

    -- collect partial results
    local partials = {}
    local waiting = {}
    for _, id in ipairs(indexers) do waiting[id]=true end
    local timer = os.startTimer(TIMEOUT_SEC)

    while next(waiting) do
      local event, p1, p2, p3 = os.pullEvent()
      if event=="rednet_message" then
        local from, recv, proto = p1, p2, p3
        local data = type(recv)=="table" and recv[1]
        if proto==NETWORK_PROTOCOL
           and type(data)=="table"
           and data.action=="index_result"
           and data.requestId==reqId
           and waiting[from] then

          partials[from] = data.data
          waiting[from] = nil
          print(("Received from %d, %d remaining"):format(from, countKeys(waiting)))
        end
      elseif event=="timer" and p1==timer then
        print("Timeout waiting for indexers.")
        break
      end
    end

    -- merge and reply
    local merged = buildGlobalIndex(partials)
    rednet.send(sender, {{
      action    = "index_response",
      requestId = reqId,
      data      = merged
    }}, NETWORK_PROTOCOL)
    print(("Replied to %d with merged index (%d items)"):format(sender, countKeys(merged)))
::continue::
  end
end

