-- indexer.lua
-- Inventory Indexer: responds to discovery broadcasts and indexes assigned
-- inventories. Provides extensive debug output for reliability.

local NETWORK_PROTOCOL = "inventoryNet"
local DISCOVERY_ACTION = "discover_indexers"
local DISCOVERY_REPLY  = "discover_response"


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
  local result = {}
  print(string.format("[DEBUG] Starting buildIndex with %d chest(s)", #chests))
  for i, chest in ipairs(chests) do
    print(string.format("[DEBUG] [%d/%d] Processing chest '%s'", i, #chests, chest))
    local ok, per = pcall(peripheral.wrap, chest)
    if not ok or not per then
      print(string.format("[ERROR] Could not wrap peripheral '%s': %s", chest, tostring(per)))
    else
      local slots = {}
      local count = 0
      for slot, item in pairs(per.list()) do
        if item and item.name then
          slots[slot] = { name = item.name, count = item.count }
          count = count + 1
          print(string.format("  [ITEM] slot=%d name=%s count=%d", slot, item.name, item.count))
        end
      end
      result[chest] = slots
      print(string.format("[DEBUG] Chest '%s' indexed (%d slot entries)", chest, count))
    end
  end
  return result
end

-- Main loop: receive assignments and respond
if not initRednet() then
  error("[FATAL] No modem found for rednet.")
end

print("[INFO] indexer.lua running, waiting for commands...")
while true do
  local sender, msg, proto = rednet.receive(NETWORK_PROTOCOL)
  local data = type(msg) == "table" and msg[1]
  if proto ~= NETWORK_PROTOCOL or type(data) ~= "table" then
    print("[WARN] Ignored malformed packet from " .. tostring(sender))
  elseif data.action == DISCOVERY_ACTION and data.requestId then
    -- Respond to discovery broadcast
    rednet.send(sender, {{ action = DISCOVERY_REPLY, requestId = data.requestId }}, NETWORK_PROTOCOL)
    print(string.format("[DEBUG] Responded to discovery request %d from %d", data.requestId, sender))
  elseif data.action == "index" and data.requestId and type(data.chests) == "table" then
    print(string.format("[INFO] Received index request %d with %d inventory blocks", data.requestId, #data.chests))
    print("[DEBUG] Assigned inventory list:", textutils.serialise(data.chests))
    logVisiblePeripherals()

    -- Build index for assigned inventories
    local result = buildIndex(data.chests)

    local reply = {
      action    = "index_result",
      requestId = data.requestId,
      data      = result
    }
    rednet.send(sender, {reply}, NETWORK_PROTOCOL)
    print(string.format("[INFO] index_result sent for req %d", data.requestId))

  else
    print("[WARN] Received unknown message type from " .. tostring(sender))
  end
end

