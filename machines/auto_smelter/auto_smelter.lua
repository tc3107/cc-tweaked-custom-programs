-- Smart AutoSmelter for CC:Tweaked
-- Enhanced with robust error reporting and streamlined output

-- Configuration files and settings
local FURNACES_FILE       = "furnaces.txt"
local SMELTABLE_FILE      = "smeltable.txt"
local OUTPUT_CHEST        = "minecraft:chest_X"  -- set your output chest here
local COAL_ITEM           = "minecraft:coal"
local FUEL_PER_COAL       = 8            -- smelts provided per coal piece
local MAX_FUEL_THRESHOLD  = 2            -- refill when fuel count falls below this
local PROGRESS_BAR_WIDTH  = 20           -- characters in the progress bar
local FUEL_CHECK_INTERVAL = 5            -- seconds between coal checks

-- Utility: trim whitespace
local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

-- Read all lines with error reporting
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
  for line in content:gmatch("([^\n]+)") do
    line = trim(line)
    if #line > 0 then table.insert(lines, line) end
  end
  return lines
end

-- Write all lines with error reporting
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
    if not ok or not fileOrErr then
      print("[ERROR] Failed to create file " .. path .. ": " .. tostring(fileOrErr))
    else
      fileOrErr.close()
      print("[INFO] Created missing file: " .. path)
    end
  end
end

-- Load furnaces list, prompting until valid entries
local function loadFurnaces()
  ensureFile(FURNACES_FILE)
  while true do
    local names = readLines(FURNACES_FILE)
    local furnaces = {}
    for _, name in ipairs(names) do
      if peripheral.isPresent(name) then
        local ok, per = pcall(peripheral.wrap, name)
        if ok and per then
          table.insert(furnaces, { name = name, per = per })
        else
          print("[ERROR] Could not wrap furnace: " .. name)
        end
      else
        print("[WARN] Furnace not present: " .. name)
      end
    end
    if #furnaces > 0 then
      print("\n[INFO] Loaded " .. #furnaces .. " furnaces from " .. FURNACES_FILE)
      return furnaces
    end
    print("[ERROR] No valid furnaces in " .. FURNACES_FILE)
    print("Add furnace peripheral names (one per line), then press Enter to retry...")
    read()
  end
end

-- Discover storage peripherals (exclude furnaces)
local function getStoragePeripherals(furnaces)
  local furnaceSet = {}
  for _, f in ipairs(furnaces) do furnaceSet[f.name] = true end
  local storage = {}
  for _, name in ipairs(peripheral.getNames()) do
    if not furnaceSet[name] then
      local ok, per = pcall(peripheral.wrap, name)
      if ok and per and type(per.list) == 'function' then
        table.insert(storage, name)
      end
    end
  end
  if #storage == 0 then
    print("\n[WARN] No storage peripherals found (excluding furnaces)")
  else
    print("\n[INFO] Found " .. #storage .. " storage peripherals")
  end
  return storage
end

-- Build inventory index from storage peripherals
local function buildInventoryIndex(storageNames)
  local index = {}
  for _, chest in ipairs(storageNames) do
    local per = peripheral.wrap(chest)
    if per then
      local ok, items = pcall(per.list)
      if ok and type(items) == 'table' then
        for slot, item in pairs(items) do
          if item and item.name then
            local name, count = item.name, item.count
            index[name] = index[name] or { total = 0, sources = {} }
            index[name].total = index[name].total + count
            table.insert(index[name].sources, { chest = chest, slot = slot, count = count })
          end
        end
      else
        print("[ERROR] Could not list items in " .. chest)
      end
    else
      print("[ERROR] Could not wrap storage peripheral: " .. chest)
    end
  end
  if not next(index) then
    print("[WARN] Inventory index is empty")
  end
  return index
end

-- Move output items from furnace to output chest
local function collectOutput(furnaces)
  for _, f in ipairs(furnaces) do
    local out = f.per.getItemDetail(3)
    if out and out.count and out.count > 0 then
      local moved = f.per.pushItems(OUTPUT_CHEST, 3, out.count)
    end
  end
end

-- Dynamic fuel & output monitoring coroutine
local function monitorFurnaces(furnaces, storage)
  local warnedCoal = false
  while true do
    collectOutput(furnaces)
    local idx = buildInventoryIndex(storage)
    for _, f in ipairs(furnaces) do
      local fuel = f.per.getItemDetail(2)
      local fuelCount = (fuel and fuel.count) or 0
      if fuelCount < MAX_FUEL_THRESHOLD then
        local inDet = f.per.getItemDetail(1)
        local toSmelt = (inDet and inDet.count) or 0
        local needed = math.ceil(toSmelt / FUEL_PER_COAL)
        local give = math.max(1, needed - fuelCount)
        local coalEntry = idx[COAL_ITEM]
        if coalEntry and coalEntry.total > 0 then
          local rem = give
          for _, s in ipairs(coalEntry.sources) do
            if rem <= 0 then break end
            local srcPer = peripheral.wrap(s.chest)
            local moved = srcPer.pushItems(f.name, s.slot, rem, 2)
            if moved and moved > 0 then rem = rem - moved end
          end
          if give - rem > 0 then
            print("\n[INFO] Refueled " .. (give-rem) .. " coal into " .. f.name)
          end
          warnedCoal = false
        else
          if not warnedCoal then
            print("\n[ERROR] " .. COAL_ITEM .. " unavailable in storage network")
            warnedCoal = true
          end
        end
      end
    end
    sleep(FUEL_CHECK_INTERVAL)
  end
end

-- Display real-time smelting progress (input only)
local function displayProgress(furnaces)
  local capacity = #furnaces * 64
  local _, y = term.getCursorPos()
  while true do
    local totalIn = 0
    for _, f in ipairs(furnaces) do
      local inDet = f.per.getItemDetail(1)
      if inDet then totalIn = totalIn + inDet.count end
    end
    if totalIn == 0 then break end
    local pct = math.floor((totalIn / capacity) * 100)
    local filled = math.floor((pct / 100) * PROGRESS_BAR_WIDTH)
    local bar = string.rep("#", filled) .. string.rep("-", PROGRESS_BAR_WIDTH - filled)
    term.setCursorPos(1, y)
    term.clearLine()
    write(string.format("Progress:[%s]%d%% %d/%d", bar, pct, totalIn, capacity))
    sleep(1)
  end
  print("\n[SUCCESS] Smelting complete: all input slots empty")
end

-- Main smelting logic
local function smeltMain(furnaces, storage)
  ensureFile(SMELTABLE_FILE)
  local list = readLines(SMELTABLE_FILE)
  local smeltable = {}
  for _, item in ipairs(list) do smeltable[item] = true end
  if #list == 0 then print("\n[WARN] No smeltable items defined in " .. SMELTABLE_FILE) end

  while true do
    io.write("Item to smelt (or 'skip'): ")
    local choice = trim(read() or "")
    if choice:lower() == "skip" then break end
    local norm = choice:lower():gsub("%s+", "_")
    local fullName, sug = nil, {}
    for item in pairs(smeltable) do
      if item:find(norm,1,true) then fullName = item end
      if #sug<5 and item:find(norm) then table.insert(sug,item) end
    end
    if not fullName then
      print("\n[ERROR] '"..choice.."' not in smeltable list")
      if #sug>0 then print("Suggestions:") for _,s in ipairs(sug) do print("- "..s) end end
      goto cont
    end

    local idx = buildInventoryIndex(storage)
    local entry = idx[fullName]
    if not entry then print("\n[ERROR] No '"..fullName.."' found in storage") return end
    local available = entry.total
    local maxCap = #furnaces * 64
    print(string.format("\n[INFO] Found %d %s | Capacity: %d", available, fullName, maxCap))

    io.write("Quantity to smelt: ")
    local qty = tonumber(trim(read() or ""))
    if not qty or qty<1 or qty>available or qty>maxCap then
      print("\n[ERROR] Choose 1 to "..math.min(available,maxCap))
      goto cont
    end

    local perF = math.floor(qty/#furnaces)
    local rem = qty%#furnaces
    for i,f in ipairs(furnaces) do
      local target = perF + (i<=rem and 1 or 0)
      local moved = 0
      if target>0 then
        local inDet = f.per.getItemDetail(1)
        local used = (inDet and inDet.count) or 0
        local free = 64 - used
        local send = math.min(target,free)
        for _,s in ipairs(entry.sources) do
          if send<=0 then break end
          local srcPer=peripheral.wrap(s.chest)
          local ok=srcPer.pushItems(f.name,s.slot,send,1)
          if ok and ok>0 then moved=moved+ok; send=send-ok end
        end
      end
      print(string.format("Furnace %d: moved %d of %d",i,moved,target))
    end
    break
    ::cont::
  end
  displayProgress(furnaces)
end

-- Entry point
local function main()
  ensureFile(FURNACES_FILE)
  ensureFile(SMELTABLE_FILE)
  local furnaces = loadFurnaces()
  local storage = getStoragePeripherals(furnaces)
  if #storage==0 then print("\n[WARN] No storage found; cannot smelt") end
  parallel.waitForAll(
    function() monitorFurnaces(furnaces,storage) end,
    function() smeltMain(furnaces,storage) end
  )
end

main()
