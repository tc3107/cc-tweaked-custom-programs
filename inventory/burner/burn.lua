-- burn.lua: Send all items from an input chest to an auto-incinerator
-- Configuration: set your networked input and output chest peripheral names here
local inputChest  = "minecraft:chest_"
local incineratorChest = "minecraft:chest_"

-- Prompt user and read a line
local function prompt(msg)
  write(msg .. " ")
  return read()
end

-- Check if a chest is empty
local function isChestEmpty(name)
  local per = peripheral.wrap(name)
  if not per then return true end
  local contents = per.list()
  return next(contents) == nil
end

-- Check if a chest is full (no free slots)
local function isChestFull(name)
  local per = peripheral.wrap(name)
  if not per then return true end
  local total  = per.size()
  local used   = 0
  for _, item in pairs(per.list()) do
    used = used + 1
  end
  return (total - used) <= 0
end

-- Main burn logic
local function main()
  -- Ensure chests exist
  if not peripheral.isPresent(inputChest) then
    print("Error: Input chest '"..inputChest.."' not found.")
    return
  end
  if not peripheral.isPresent(incineratorChest) then
    print("Error: Output chest '"..incineratorChest.."' not found.")
    return
  end

  -- Confirm action
  local answer = prompt("WARNING: This will destroy ALL items in "..inputChest..". Continue? (y/n)")
  if not answer or answer:lower() ~= "y" then
    print("Aborted.")
    return
  end

  local burnedCount = 0
  local srcPer = peripheral.wrap(inputChest)

  -- Loop until source empty or destination full
  while true do
    if isChestEmpty(inputChest) then
      print("Source chest is empty. Burn complete.")
      break
    end
    if isChestFull(incineratorChest) then
      print("Output chest is full. Stopping burn.")
      break
    end

    -- Fetch next slot to burn
    local contents = srcPer.list()
    for slot, item in pairs(contents) do
      -- attempt to push entire stack to incinerator
      local moved = srcPer.pushItems(incineratorChest, slot, item.count)
      if moved and moved > 0 then
        burnedCount = burnedCount + moved
      end
      break -- process one slot per iteration
    end
  end

  print("Total items burned: "..burnedCount)
end

main()
