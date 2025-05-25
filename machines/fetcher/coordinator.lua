-- coordinator.lua
-- Central Server: reads indexer IDs, partitions workloads, aggregates results, and returns the merged index.

local INDEXERS_FILE = "indexers.txt"
local NETWORK_PROTOCOL = "inventoryNet"
local TIMEOUT_SEC = 30

-- Count number of keys in a table
local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Utility: read lines from a file into a table of numbers
local function readIndexers(fname)
  local ids = {}
  local f = fs.open(fname, "r")
  if not f then
    error("Cannot open "..fname)
  end
  while true do
    local line = f.readLine()
    if not line then break end
    local n = tonumber(line:match("^%s*(%d+)%s*$"))
    if n then table.insert(ids, n) end
  end
  f.close()
  return ids
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

-- Merge multiple index tables into one
local function mergeIndices(partials)
  local merged = {}
  for _, idx in pairs(partials) do
    for name, data in pairs(idx) do
      if not merged[name] then
        merged[name] = { total=0, sources={} }
      end
      merged[name].total = merged[name].total + data.total
      for _, src in ipairs(data.sources) do
        table.insert(merged[name].sources, src)
      end
    end
  end
  return merged
end

-- Build an inventory index for given chest list
local function buildIndexFor(chests)
  local index = {}
  for _, chest in ipairs(chests) do
    local per = peripheral.wrap(chest)
    for slot, item in pairs(per.list()) do
      local name, count = item.name, item.count
      index[name] = index[name] or { total=0, sources={} }
      index[name].total = index[name].total + count
      table.insert(index[name].sources, {
        chest = chest, slot = slot, count = count
      })
    end
  end
  return index
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

local indexers = readIndexers(INDEXERS_FILE)
print("Loaded "..#indexers.." indexers.")

local requestCounter = 0

while true do
  local sender, msg = rednet.receive(NETWORK_PROTOCOL)
  local data = type(msg)=="table" and msg[1]
  if sender and type(msg)=="table" and type(data)=="table" and data.action=="index_request" then
    requestCounter = requestCounter + 1
    local reqId = requestCounter
    print(("Index request #%d from %d"):format(reqId, sender))

    -- discover chests & partition
    local allChests = findChests()
    local chunks = partition(allChests, #indexers)

    -- dispatch to indexers
    for i, idxId in ipairs(indexers) do
      local payload = {
        action     = "index",
        requestId  = reqId,
        chests     = chunks[i]
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
    local merged = mergeIndices(partials)
    rednet.send(sender, {{
      action    = "index_response",
      requestId = reqId,
      data      = merged
    }}, NETWORK_PROTOCOL)
    print(("Replied to %d with merged index (%d items)"):format(sender, countKeys(merged)))
  end
end

