-- inventory_control.lua
local protocol = "sort"
local hostname = "inventory_control"

-- Define item → destination chest map
local destinationMap = {
    ["minecraft:cobblestone"] = { "minecraft:chest_1" },
    ["minecraft:dirt"] = { "minecraft:chest_2" }
    -- Add more mappings here
}

local overflowChest = "chest_overflow"

-- Start network
rednet.open("back")
rednet.host(protocol, hostname)
print("Inventory server online as '" .. hostname .. "' using protocol '" .. protocol .. "'.")

-- Helper to get free space in a chest
local function getFreeSpace(chestName)
    print("Checking free space in chest: " .. chestName)
    if not peripheral.isPresent(chestName) then
        print("Peripheral not found: " .. chestName)
        return -1
    end
    local chest = peripheral.wrap(chestName)
    local total = chest.size()
    local used = 0
    for _, item in pairs(chest.list()) do
        used = used + 1
    end
    print("Free slots in " .. chestName .. ": " .. (total - used))
    return total - used
end

-- Move item from input chest to best output
local function moveItem(chestName, slot, itemName, count)
    print("Attempting to move item: " .. itemName .. " from " .. chestName .. " (slot " .. slot .. ", count " .. count .. ")")
    local targets = destinationMap[itemName]
    if not targets then
        print("No targets found for item: " .. itemName)
        return false, "No destination for item: " .. itemName
    end

    for _, target in ipairs(targets) do
        print("Trying target: " .. target)
        if peripheral.isPresent(target) then
            local free = getFreeSpace(target)
            if free > 0 then
                print("Found space in: " .. target)
                local moved = peripheral.wrap(chestName).pushItems(target, slot, count)
                if moved > 0 then
                    print("Moved " .. moved .. "x " .. itemName .. " to " .. target)
                    return true, "Moved " .. moved .. "x " .. itemName .. " to " .. target
                else
                    print("PushItems returned 0 moved.")
                end
            else
                print("No free space in target: " .. target)
            end
        else
            print("Target chest not present: " .. target)
        end
    end

    if overflowChest and peripheral.isPresent(overflowChest) then
        print("Trying overflow chest: " .. overflowChest)
        local moved = peripheral.wrap(chestName).pushItems(overflowChest, slot, count)
        if moved > 0 then
            print("Sent " .. moved .. "x " .. itemName .. " to overflow")
            return true, "Sent " .. itemName .. " to overflow"
        else
            print("PushItems to overflow returned 0 moved.")
        end
    else
        print("Overflow chest not present or not defined.")
    end

    return false, "No space for item: " .. itemName
end

-- Sort contents of a single chest
local function sortChest(chestName)
    print("Sorting chest: " .. chestName)
    if not peripheral.isPresent(chestName) then
        print("ERROR: Chest not found: " .. chestName)
        return false, "Chest not found: " .. chestName
    end

    local chest = peripheral.wrap(chestName)
    local contents = chest.list()
    local result = {}

    for slot, item in pairs(contents) do
        print("Found item in slot " .. slot .. ": " .. item.name .. " x" .. item.count)
        local success, message = moveItem(chestName, slot, item.name, item.count)
        table.insert(result, message)
    end

    return true, result
end

-- Server loop
while true do
    print("Waiting for message on protocol '" .. protocol .. "'...")
    local senderId, msg, proto = rednet.receive(protocol)
    print("Received message from ID " .. senderId)

    local reply = {}

    if type(msg) == "table" then
        for _, chestName in ipairs(msg) do
            print("Requested to sort chest: " .. chestName)
            local ok, result = sortChest(chestName)
            if not ok then
                table.insert(reply, "- " .. result)
            else
                for _, line in ipairs(result) do
                    table.insert(reply, "+ " .. line)
                end
            end
        end
    else
        print("Invalid request type received: " .. type(msg))
        table.insert(reply, "Invalid request: expected list of chests.")
    end

    print("Sending reply to ID " .. senderId)
    rednet.send(senderId, reply, protocol)
end
