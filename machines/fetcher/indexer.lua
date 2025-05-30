-- indexer.lua: Worker that scans assigned storage and reports contents

local protocol = "fetcher"

-- Open all modems
local function openAllModems()
  local sides = {"left","right","top","bottom","front","back"}
  for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
      if not rednet.isOpen(side) then
        rednet.open(side)
      end
    end
  end
end

local function scan(chests)
  local data = {}
  for _, name in ipairs(chests) do
    if peripheral.isPresent(name) then
      local per = peripheral.wrap(name)
      local chestData = {}
      for slot, item in pairs(per.list()) do
        if item then chestData[slot] = item end
      end
      data[name] = chestData
    end
  end
  return data
end

local function main()
  openAllModems()
  local id = os.getComputerID()
  print("Indexer "..id.." ready")
  while true do
    local sender, msg, proto = rednet.receive(protocol)
    if type(msg) == "table" and msg.type == "identify" then
      rednet.send(sender, {type="identify", id=id}, protocol)
    elseif type(msg)=="table" and msg.type=="scan" and type(msg.targets)=="table" then
      local results = scan(msg.targets)
      rednet.send(sender, {type="scan", id=id, data=results}, protocol)
    end
  end
end

main()

