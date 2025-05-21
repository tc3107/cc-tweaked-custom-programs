-- Smart AutoSmelter for CC:Tweaked
-- Enhanced with robust error reporting and usability improvements

-- Configuration files
local FURNACES_FILE = "furnaces.txt"
local SMELTABLE_FILE = "smeltable.txt"
local COAL_ITEM = "minecraft:coal"
local FUEL_PER_COAL = 8          -- number of smelts per coal
local MAX_FUEL_THRESHOLD = 2     -- below this triggers refuel
local PROGRESS_BAR_LENGTH = 10   -- characters in progress bar

-- Utility: trim whitespace
local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

-- Utility: read all lines, with error reporting
local function readLines(path)
  if not fs.exists(path) then
    print("[ERROR] File not found: " .. path)
    return {}
  end
  local file, err = fs.open(path, "r")
  if not file then
    print("[ERROR] Could not open " .. path .. ": " .. tostring(err))
    return {}
  end
  local content = file.readAll()
  file.close()
  local lines = {}
  for line in content:gmatch("([^]+)") do
    line = trim(line)
    if #line > 0 then table.insert(lines, line) end
  end
  return lines
end

-- Utility: write all lines, with error reporting
local function writeLines(path, lines)
  local file, err = fs.open(path, "w")
  if not file then
    print("[ERROR] Could not write to " .. path .. ": " .. tostring(err))
    return false
  end
  for _, line in ipairs(lines) do file.writeLine(line) end
  file.close()
  return true
end

-- Ensure a file exists, or create it
local function ensureFile(path)
  if not fs.exists(path) then
    local ok, fileOrErr = pcall(fs.open, path, "w")
    if not ok then
      print("[ERROR] Failed to create file " .. path .. ": " .. tostring(fileOrErr))
    else
      fileOrErr.close()
      print("[INFO] Created missing config file: " .. path)
    end
  end
end

-- Discover storage peripherals (exclude furnaces)
local function getStoragePeripherals()
  local storage = {}
  for _, name in ipairs(peripheral.getNames()) do
    local ok, per = pcall(peripheral.wrap, name)
    if ok and type(per.list) == 'function' then
      -- Exclude furnaces (they have getInputDetail)
      if type(per.getInputDetail) ~= 'function' then
        table.insert(storage, name)
      end
    end
  end
  if #storage == 0 then
    print("[WARN] No storage peripherals found on network.")
  else
    print("[INFO] Found " .. #storage .. " storage peripherals.")
  end
  return storage
end

-- Build inventory index: { itemName = { total=N, sources={ {chest,slot,count}, ... } } }
local function buildInventoryIndex(storages)
  local index = {}
  for _, chest in ipairs(storages) do
    local per = peripheral.wrap(chest)
    if not per then
      print("[ERROR] Failed to wrap storage peripheral: " .. chest)
    else
      local success, items = pcall(per.list)
      if not success then
        print("[ERROR] Could not list items in " .. chest)
      else
        for slot, item in pairs(items) do
          local name, count = item.name, item.count
          if not index[name] then index[name] = { total = 0, sources = {} } end
          index[name].total = index[name].total + count
          table.insert(index[name].sources, { chest = chest, slot = slot, count = count })
        end
      end
    end
  end
  return index
end

-- Load furnaces list, prompting user until at least one is found
local function loadFurnaces()
  ensureFile(FURNACES_FILE)
  while true do
    local names = readLines(FURNACES_FILE)
    local furnaces = {}
    for _, name in ipairs(names) do
      if peripheral.isPresent(name) then
        local ok, per = pcall(peripheral.wrap, name)
        if ok then table.insert(furnaces, { name = name, per = per }) end
      else
        print("[WARN] Furnace not present: " .. name)
      end
    end
    if #furnaces > 0 then
      print("[INFO] Loaded " .. #furnaces .. " furnaces from " .. FURNACES_FILE)
      return furnaces
    end
    print("[ERROR] No valid furnaces configured in " .. FURNACES_FILE)
    print("Please add furnace peripheral names (one per line), then press Enter to retry...")
    read()
  end
end

-- Dynamic fuel monitoring thread
local function monitorFuel(furnaces, storages)
  local warned = false
  while true do
    local index = buildInventoryIndex(storages)
    for _, f in ipairs(furnaces) do
      local fuelDetail = f.per.getItemDetail(2)
      local fuelCount = fuelDetail and fuelDetail.count or 0
      if fuelCount < MAX_FUEL_THRESHOLD then
        local inputDetail = f.per.getItemDetail(1)
        local toSmelt = inputDetail and inputDetail.count or 0
        local neededCoal = math.ceil(toSmelt / FUEL_PER_COAL)
        local give = math.max(1, neededCoal - fuelCount)
        local coalData = index[COAL_ITEM]
        if coalData and coalData.total > 0 then
          local remaining = give
          for _, src in ipairs(coalData.sources) do
            if remaining <= 0 then break end
            local chestPer = peripheral.wrap(src.chest)
            local moved = chestPer.pushItems(f.name, src.slot, remaining, 2)
            if moved and moved > 0 then remaining = remaining - moved end
          end
          if give > remaining then
            print(string.format("[INFO] Refueled %d coal into %s (had %d)", give - remaining, f.name, fuelCount))
          end
          warned = false
        else
          if not warned then
            print("[ERROR] " .. COAL_ITEM .. " not found in network!")
            warned = true
          end
        end
      end
    end
    sleep(1)
  end
end

-- Display real-time progress bar
local function displayProgress(furnaces)
  local capacity = #furnaces * 64
  local _, startY = term.getCursorPos()
  while true do
    local totalItems = 0
    for _, f in ipairs(furnaces) do
      for slot = 1, 3 do
        local d = f.per.getItemDetail(slot)
        if d then totalItems = totalItems + d.count end
      end
    end
    if totalItems == 0 then break end
    local pct = math.floor((totalItems / capacity) * 100)
    local filled = math.floor((pct / 100) * PROGRESS_BAR_LENGTH)
    local bar = string.rep("█", filled) .. string.rep("░", PROGRESS_BAR_LENGTH - filled)
    term.setCursorPos(1, startY)
    term.clearLine()
    write(string.format("Progress: [%s] %3d%% (%d/%d)\n", bar, pct, totalItems, capacity))
    sleep(1)
  end
  print("[SUCCESS] All furnaces are empty. Smelting complete.")
end

-- Main smelting logic with robust user feedback
local function smeltMain(furnaces, storages)
  ensureFile(SMELTABLE_FILE)
  local list = readLines(SMELTABLE_FILE)
  local smeltable = {}
  for _, item in ipairs(list) do smeltable[item] = true end
  if #list == 0 then
    print("[WARN] No smeltable items defined in " .. SMELTABLE_FILE)
  end

  while true do
    write("Enter item to smelt (or 'skip'): ")
    local choice = trim(read() or "")
    if choice:lower() == "skip" then break end

    -- Normalize and match
    local norm = choice:lower():gsub("%s+","_")
    local fullName, suggestions = nil, {}
    for item in pairs(smeltable) do
      if item:find(norm, 1, true) then fullName = item end
      if #suggestions < 5 and item:find(norm) then table.insert(suggestions, item) end
    end
    if not fullName then
      print("[ERROR] '" .. choice .. "' not smeltable.")
      if #suggestions > 0 then
        print("Did you mean:")
        for _, s in ipairs(suggestions) do print("  - " .. s) end
      end
      goto continue_prompt
    end

    local index = buildInventoryIndex(storages)
    if not next(index) then
      print("[ERROR] No items indexed. Check storage connections.")
      return
    end

    local available = (index[fullName] and index[fullName].total) or 0
    local maxCap = #furnaces * 64
    print(string.format("[INFO] Available: %d, Total furnace capacity: %d", available, maxCap))

    write("Quantity to smelt: ")
    local qty = tonumber(trim(read() or ""))
    if not qty or qty < 1 or qty > available or qty > maxCap then
      print("[ERROR] Invalid quantity. Enter a number from 1 to " .. math.min(available, maxCap))
      goto continue_prompt
    end

    -- Distribute items
    local perF = math.floor(qty / #furnaces)
    local rem = qty % #furnaces
    for i, f in ipairs(furnaces) do
      local target = perF + (i <= rem and 1 or 0)
      local movedTotal = 0
      if target > 0 then
        local inDet = f.per.getItemDetail(1)
        local used = inDet and inDet.count or 0
        local free = 64 - used
        local toSend = math.min(target, free)
        local remSend = toSend
        for _, src in ipairs(index[fullName].sources) do
          if remSend <= 0 then break end
          local chPer = peripheral.wrap(src.chest)
          local moved = chPer.pushItems(f.name, src.slot, remSend, 1)
          if moved and moved > 0 then
            remSend = remSend - moved
            movedTotal = movedTotal + moved
          end
        end
      end
      if movedTotal < target then
        print(string.format("[WARN] Furnace %d: moved only %d of %d %s", i, movedTotal, target, fullName))
      else
        print(string.format("[INFO] Furnace %d: received %d %s", i, movedTotal, fullName))
      end
    end
    break

    ::continue_prompt::
  end

  displayProgress(furnaces)
end

-- Entry point
local function main()
  ensureFile(FURNACES_FILE)
  ensureFile(SMELTABLE_FILE)

  local furnaces = loadFurnaces()
  local storages = getStoragePeripherals()
  if #storages == 0 then
    print("[WARN] No storage peripherals available. The script may not function correctly.")
  end
  parallel.waitForAll(
    function() monitorFuel(furnaces, storages) end,
    function() smeltMain(furnaces, storages) end
  )
end

-- Start
main()
