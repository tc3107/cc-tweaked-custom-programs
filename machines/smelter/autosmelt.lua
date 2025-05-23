-- Smart AutoSmelter for CC:Tweaked (Reworked Architecture)

-- Configuration files
local FURNACES_FILE       = "furnaces.txt"
local SMELTABLE_FILE      = "smeltable.txt"
local FUELS_FILE          = "fuels.txt"
local OUTPUT_CHEST        = "minecraft:chest_43"
local MAX_FUEL_THRESHOLD  = 4
local PROGRESS_BAR_WIDTH  = 20
local CHECK_INTERVAL      = 0.5
local TEXT_SCALE          = 1

-- State variables
local furnaces = {}
local storage  = {}
local fuels    = {}
local itemCounts = {}
local progressCapacity = 0

-- Utility functions ------------------------------------------------------
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

local function readLines(path)
  if not fs.exists(path) then return {} end
  local f = fs.open(path, "r")
  if not f then return {} end
  local content = f.readAll()
  f.close()
  local lines = {}
  for line in content:gmatch("([^\n]+)") do
    line = trim(line)
    if #line > 0 then table.insert(lines, line) end
  end
  return lines
end

local function ensureFile(path)
  if not fs.exists(path) then
    local ok, f = pcall(fs.open, path, "w")
    if ok and f then f.close() end
  end
end

-- Display system status on monitor ---------------------------------------
local function displayStatus(message)
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
      local mon = peripheral.wrap(name)
      mon.setTextScale(TEXT_SCALE)
      mon.clear()
      mon.setCursorPos(1, 1)
      mon.write(message)
      break
    end
  end
end

-- Load peripherals -------------------------------------------------------
local function loadFurnaces()
  ensureFile(FURNACES_FILE)
  while #furnaces == 0 do
    local names = readLines(FURNACES_FILE)
    for _, name in ipairs(names) do
      if peripheral.isPresent(name) then
        local ok, p = pcall(peripheral.wrap, name)
        if ok and p then table.insert(furnaces, { name = name, per = p }) end
      end
    end
    if #furnaces == 0 then sleep(CHECK_INTERVAL) end
  end
end

local function loadFuels()
  ensureFile(FUELS_FILE)
  fuels = readLines(FUELS_FILE)
end

local function getStorage()
  local set = {}
  for _, f in ipairs(furnaces) do set[f.name] = true end
  for _, name in ipairs(peripheral.getNames()) do
    if not set[name] then
      local ok, p = pcall(peripheral.wrap, name)
      if ok and p and type(p.list) == "function" then
        table.insert(storage, name)
      end
    end
  end
end

-- Build item index from storage ------------------------------------------
local function buildIndex()
  local idx = {}
  for _, chest in ipairs(storage) do
    local p = peripheral.wrap(chest)
    if p then
      local ok, items = pcall(p.list)
      if ok and type(items) == "table" then
        for slot, item in pairs(items) do
          if item and item.name then
            idx[item.name] = idx[item.name] or {}
            table.insert(idx[item.name], { chest = chest, slot = slot })
          end
        end
      end
    end
  end
  return idx
end

-- Scanner thread ---------------------------------------------------------
local function scannerThread()
  print("[INFO] Scanning fuel levels...")
  while true do
    local idx = buildIndex()
    for _, f in ipairs(furnaces) do
      local ok, inD = pcall(f.per.getItemDetail, 1)
      itemCounts[f.name] = (ok and inD and inD.count) or 0

      local ok_out, outD = pcall(f.per.getItemDetail, 3)
      if ok_out and outD and outD.count > 0 then
        f.per.pushItems(OUTPUT_CHEST, 3, outD.count)
      end

      local ok_fuel, fuelD = pcall(f.per.getItemDetail, 2)
      local fc = (ok_fuel and fuelD and fuelD.count) or 0
      if fc < MAX_FUEL_THRESHOLD then
        for _, name in ipairs(fuels) do
          local slots = idx[name]
          if slots then
            local need = MAX_FUEL_THRESHOLD - fc
            for _, s in ipairs(slots) do
              if need <= 0 then break end
              local cp = peripheral.wrap(s.chest)
              local moved = cp.pushItems(f.name, s.slot, need, 2)
              need = need - (moved or 0)
            end
            break
          end
        end
      end
    end
    sleep(CHECK_INTERVAL)
  end
end

-- Display thread ---------------------------------------------------------
local function displayThread()
  while progressCapacity == 0 do sleep(0) end
  local mon
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then mon = peripheral.wrap(name); break end
  end
  if mon then
    mon.setTextScale(TEXT_SCALE)
    mon.clear()
  end

  local _, startY = term.getCursorPos()
  while true do
    local total = 0
    for _, f in ipairs(furnaces) do total = total + (itemCounts[f.name] or 0) end
    local doneCount = progressCapacity - total
    local pct = math.floor(doneCount / progressCapacity * 100)
    local filled = math.floor(pct / 100 * PROGRESS_BAR_WIDTH)
    local bar = string.rep("#", filled) .. string.rep("-", PROGRESS_BAR_WIDTH - filled)

    term.setCursorPos(1, startY)
    term.clearLine()
    write(string.format("T-Progress:[%s] %d%% %d/%d", bar, pct, doneCount, progressCapacity))

    if mon then
      mon.clear()
      mon.setCursorPos(1, 1)
      mon.write(string.format("M-Progress:[%s] %d%%", bar, pct))
    end
    sleep(CHECK_INTERVAL)
  end
end

-- Insertion thread --------------------------------------------------------
local function insertionThread()
  ensureFile(SMELTABLE_FILE)
  local list = readLines(SMELTABLE_FILE)
  local smeltable = {}
  for _, name in ipairs(list) do smeltable[name] = true end

  -- compute items already in furnaces
  local totalInFurnaces = 0
  for _, f in ipairs(furnaces) do
    local ok, inD = pcall(f.per.getItemDetail, 1)
w    totalInFurnaces = totalInFurnaces + ((ok and inD and inD.count) or 0)
  end

  io.write("Item to smelt (or 'skip'): ")
  local input = trim(read() or "")
  if input:lower() == 'skip' then
    progressCapacity = totalInFurnaces
    return
  end

  -- normalize user's input
  local raw = input:lower():gsub("%s+", "_")
  local norm = raw
  if not raw:find(":", 1, true) then
    norm = "minecraft:" .. raw
  end

  local target
  -- 1) exact-match lookup
  if smeltable[norm] then
    target = norm
  else
    -- 2) fallback to first substring match
    for name in pairs(smeltable) do
      if name:find(raw, 1, true) then
        target = name
        break
      end
    end
  end

  if not target then
    print("[ERROR] Unknown smeltable: " .. input)
    return
  end

  -- build storage index and check availability
  local idx = buildIndex()
  local entry = idx[target]
  if not entry or #entry == 0 then
    print("[ERROR] No items to smelt: " .. target)
    return
  end

  local totalAvail = 0
  for _, slot in ipairs(entry) do
    local p = peripheral.wrap(slot.chest)
    local info = p.getItemDetail(slot.slot)
    if info and info.count and info.count > 0 then
      totalAvail = totalAvail + info.count
    end
  end

  if totalAvail == 0 then
    print("[ERROR] No items to smelt: " .. target)
    return
  end

  io.write(string.format("Found %d %s\n", totalAvail, target))
  io.write("Qty to smelt: ")
  local q = tonumber(trim(read() or ""))
  if not q or q <= 0 or q > totalAvail then
    print("[ERROR] Invalid quantity")
    return
  end

  progressCapacity = q + totalInFurnaces

  local perF = math.floor(q / #furnaces)
  local rem = q % #furnaces
  local neededMap = {}
  for i, f in ipairs(furnaces) do neededMap[f.name] = perF + (i <= rem and 1 or 0) end

  -- distribute items to furnaces
  for _, slot in ipairs(entry) do
    for _, f in ipairs(furnaces) do
      local need = neededMap[f.name]
      if need > 0 then
        local cp = peripheral.wrap(slot.chest)
        local moved = cp.pushItems(f.name, slot.slot, need, 1)
        neededMap[f.name] = need - (moved or 0)
      end
    end
  end
end

-- Main execution ----------------------------------------------------------
local function main()
  displayStatus("Initializing systems...")
  ensureFile(FURNACES_FILE)
  ensureFile(FUELS_FILE)
  loadFurnaces()
  getStorage()
  loadFuels()
  parallel.waitForAll(scannerThread, insertionThread, displayThread)
end

main()
