-- indexer.lua
-- Indexing Server: waits for a chest‐assignment message, indexes them, and returns the result.

local NETWORK_PROTOCOL = "inventoryNet"

-- Find and open a modem
local function initRednet()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name):match("modem") then
      rednet.open(name)
      return true
    end
  end
  return false
end

-- Build index for the given chests
local function buildIndex(chests)
  local index = {}
  for _, chest in ipairs(chests) do
    local ok, per = pcall(peripheral.wrap, chest)
    if ok and per then
      for slot, item in pairs(per.list()) do
        local name, count = item.name, item.count
        index[name] = index[name] or { total=0, sources={} }
        index[name].total = index[name].total + count
        table.insert(index[name].sources, {
          chest = chest, slot = slot, count = count
        })
      end
    end
  end
  return index
end

-- MAIN LOOP
if not initRednet() then
  error("No modem found")
end

while true do
  local sender, msg, proto = rednet.receive(NETWORK_PROTOCOL)
  if sender and msg and msg[1] then
    local data = msg[1]
    if data.action=="index" and data.requestId and data.chests then
      print(("Indexing %d chests (req %d)…"):format(#data.chests, data.requestId))
      local result = buildIndex(data.chests)
      local reply = {
        action    = "index_result",
        requestId = data.requestId,
        data      = result
      }
      rednet.send(sender, {reply}, NETWORK_PROTOCOL)
      print(("Sent result for req %d (%d item types)"):format(
        data.requestId, table.getn(result)))
    end
  end
end

