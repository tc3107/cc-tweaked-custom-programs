-- indexer.lua
-- Indexing Server: waits for chest assignment, indexes them with extensive debugging, and returns the result.

local NETWORK_PROTOCOL = "inventoryNet"

-- Initialize rednet by opening an attached modem
local function initRednet()
  for _, side in ipairs(peripheral.getNames()) do
    local ptype = peripheral.getType(side)
    if ptype == "modem" or ptype == "wireless_modem" then
      rednet.open(side)
      print("[DEBUG] rednet opened on ", side)
      return true
    end
  end
  return false
end

-- Log visible peripherals to help debug chest detection
local function logVisiblePeripherals()
  print("[DEBUG] Visible peripherals:")
  for _, name in ipairs(peripheral.getNames()) do
    print(string.format("  - %s (type=%s)", name, peripheral.getType(name)))
  end
end

-- Build index for the given list of chest names (with debug)
local function buildIndex(chests)
  local index = {}
  print(string.format("[DEBUG] Starting buildIndex with %d chest(s)", #chests))
  for i, chest in ipairs(chests) do
    print(string.format("[DEBUG] [%d/%d] Processing chest '%s'", i, #chests, chest))
    -- Attempt to wrap the peripheral
    local ok, per = pcall(peripheral.wrap, chest)
    if not ok or not per then
      print(string.format("[ERROR] Could not wrap peripheral '%s': %s", chest, tostring(per)))
    else
      -- List items in this chest
      local items = per.list()
      print(string.format("[DEBUG] Chest '%s' contains %d slot(s)", chest, #items))
      for slot, item in pairs(items) do
        -- item has fields: name, count
        if item and item.name then
          print(string.format("  [ITEM] slot=%d name=%s count=%d", slot, item.name, item.count))
          -- Initialize index entry if needed
          if not index[item.name] then
            index[item.name] = { total = 0, sources = {} }
          end
          -- Accumulate
          index[item.name].total = index[item.name].total + item.count
          table.insert(index[item.name].sources, { chest = chest, slot = slot, count = item.count })
        else
          print(string.format("  [WARN] slot=%d in chest='%s' has no item data", slot, chest))
        end
      end
    end
  end
  print(string.format("[DEBUG] buildIndex complete: found %d unique item type(s)", #index))
  return index
end

-- Main loop: receive assignments and respond
if not initRednet() then
  error("[FATAL] No modem found for rednet.")
end

print("[INFO] indexer.lua is running and waiting for index requests...")
while true do
  local sender, msg, proto = rednet.receive(NETWORK_PROTOCOL)
  if sender and msg and msg[1] then
    local data = msg[1]
    if data.action == "index" and data.requestId and data.chests then
      print(string.format("[INFO] Received index request %d with %d chest(s)", data.requestId, #data.chests))
      print("[DEBUG] Assigned chest list:", textutils.serialise(data.chests))
      logVisiblePeripherals()

      -- Build and send index
      local result = buildIndex(data.chests)
      print(string.format("[INFO] Sending index_result for req %d: %d item type(s)", data.requestId, #result))
      local reply = {
        action = "index_result",
        requestId = data.requestId,
        data = result
      }
      rednet.send(sender, {reply}, NETWORK_PROTOCOL)
      print(string.format("[INFO] index_result sent for req %d", data.requestId))
    else
      print("[WARN] Received unknown or malformed message: ", textutils.serialise(msg))
    end
  end
end
