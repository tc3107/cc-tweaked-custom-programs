-- fetch.lua: Distributed item fetch system 

-- Configuration
local outputChest = "minecraft:chest_"
local identifyTimeout = 1     -- seconds to wait for indexer discovery
local responseTimeout = 10    -- seconds to wait for scan results
local protocol = "fetcher"

-- Utility: open all attached modems
local function openAllModems()
  local sides = {"left","right","top","bottom","front","back"}
  for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" and not rednet.isOpen(side) then
      rednet.open(side)
    end
  end
end

-- Utility: gather all storage peripherals on the network, except the output chest
local function findStorage()
  local list = {}
  for _, name in ipairs(peripheral.getNames()) do
    if (name:match("minecraft:chest_") or name:match("minecraft:barrel_"))
       and name ~= outputChest then
      table.insert(list, name)
    end
  end
  return list
end

-- Utility: split work across indexers evenly
local function assignWork(peripherals, indexers)
  local tasks = {}
  for _, id in ipairs(indexers) do tasks[id] = {} end
  if #indexers == 0 then return tasks end
  for i, name in ipairs(peripherals) do
    local idx = indexers[((i-1) % #indexers) + 1]
    table.insert(tasks[idx], name)
  end
  return tasks
end

-- Utility: combine results from indexers
local function mergeResults(all)
  local combined = {}
  for _, data in pairs(all) do
    for chest, slots in pairs(data) do
      combined[chest] = slots
    end
  end
  return combined
end

-- Build item index from merged data
local function buildIndex(storageMap)
  local index = {}
  for chest, slots in pairs(storageMap) do
    for slot, item in pairs(slots) do
      local name = item.name
      if not index[name] then
        index[name] = { total = 0, sources = {} }
      end
      index[name].total = index[name].total + item.count
      table.insert(index[name].sources, {
        chest = chest,
        slot = slot,
        count = item.count
      })
    end
  end
  return index
end

-- Determine output chest to use (network-only)
local function getOutputChest()
  if outputChest == "" then
    print("Error: outputChest not configured.")
    return nil
  end
  if peripheral.isPresent(outputChest) then
    return outputChest
  else
    print("Error: Network chest '"..outputChest.."' not found.")
    return nil
  end
end

-- Capture simple item counts of a chest
local function snapshotChest(name)
  local per = peripheral.wrap(name)
  local counts = {}
  for _, item in pairs(per.list()) do
    if item then
      counts[item.name] = (counts[item.name] or 0) + item.count
    end
  end
  return counts
end

-- Calculate free slots
local function getFreeSpace(name)
  local per = peripheral.wrap(name)
  local total = per.size()
  local used = 0
  for _, item in pairs(per.list()) do
    if item then used = used + 1 end
  end
  return total - used
end

-- Fetch items into output chest
local function retrieve(itemName, amount, index, out)
  local needed = amount
  local sources = index[itemName].sources
  local partial, full = {}, {}
  for _, src in ipairs(sources) do
    local per = peripheral.wrap(src.chest)
    local detail = per.getItemDetail(src.slot)
    local max = detail and detail.maxCount or 64
    if src.count < max then
      table.insert(partial, src)
    else
      table.insert(full, src)
    end
  end
  for _, list in ipairs({partial, full}) do
    for _, src in ipairs(list) do
      if needed <= 0 then break end
      if getFreeSpace(out) <= 0 then
        print("Output chest full. Stopping early.")
        return amount - needed
      end
      local per = peripheral.wrap(src.chest)
      local take = math.min(src.count, needed)
      local moved = per.pushItems(out, src.slot, take)
      if moved and moved > 0 then
        needed = needed - moved
      end
    end
  end
  return amount - needed
end

-- Main logic
local function main()
  openAllModems()

  local out = getOutputChest()
  if not out then return end

  -- 1. discover indexers
  rednet.broadcast({type="identify"}, protocol)
  local indexers = {}
  local deadline = os.clock() + identifyTimeout
  while os.clock() < deadline do
    local id, msg = rednet.receive(protocol, deadline - os.clock())
    if id and type(msg)=="table" and msg.type=="identify" then
      table.insert(indexers, msg.id or id)
    end
  end

  -- 2. find storage peripherals (network, minus outputChest)
  local periphs = findStorage()
  if #periphs == 0 then
    print("No storage peripherals found.")
    return
  end

  -- 3. handle standalone vs distributed
  local results = {}
  if #indexers == 0 then
    print("No indexers found. Running standalone scan...")
    local data = {}
    for _, chest in ipairs(periphs) do
      if peripheral.isPresent(chest) then
        local per = peripheral.wrap(chest)
        local chestData = {}
        for slot, item in pairs(per.list()) do
          if item then chestData[slot] = item end
        end
        data[chest] = chestData
      end
    end
    results[os.getComputerID()] = data
  else
    -- distribute workload
    local tasks = assignWork(periphs, indexers)
    for id, list in pairs(tasks) do
      rednet.send(id, {type="scan", targets=list}, protocol)
    end
    -- collect responses
    local remaining = {}
    for _, id in ipairs(indexers) do remaining[id] = true end
    local deadline2 = os.clock() + responseTimeout
    while next(remaining) and os.clock() < deadline2 do
      local id, msg = rednet.receive(protocol, deadline2 - os.clock())
      if id and type(msg)=="table" and msg.type=="scan" and remaining[msg.id] then
        results[msg.id] = msg.data
        remaining[msg.id] = nil
      end
    end
    if next(remaining) then
      print("Timed out waiting for some indexers.")
      return
    end
  end

  -- combine and index
  local storageMap = mergeResults(results)
  local index = buildIndex(storageMap)

  -- user prompt
  write("Item name: ")
  local input = read()
  if not input then return end
  input = input:lower():gsub("%s+","_")
  local targetName
  for name in pairs(index) do
    local base = name:match(":(.+)") or name
    if base == input then
      targetName = name
      break
    end
  end
  if not targetName then
    print("Item not found")
    return
  end

  local available = index[targetName].total
  print("Available: "..available)
  write("Quantity: ")
  local qty = tonumber(read()) or 0
  if qty < 1 or qty > available then
    print("Invalid amount")
    return
  end

  local before = snapshotChest(out)
  local moved = retrieve(targetName, qty, index, out)
  local after = snapshotChest(out)
  local diff = (after[targetName] or 0) - (before[targetName] or 0)
  if diff >= qty then
    print("Fetched "..qty.." items successfully.")
  else
    print("Only moved "..diff.." items.")
  end
end

main()
