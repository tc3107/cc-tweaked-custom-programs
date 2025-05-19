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
    if not peripheral.isPresent(chestName) then return -1 end
    local chest = peripheral.wrap(chestName)
    local total = chest.size()
    local used = 0
    for _, item in pairs(chest.list()) do
        used = used + 1
    end
    return total - used
end

-- Move item from input chest to best output
local function moveItem(chestName, slot, itemName, count)
    local targets = destinationMap[itemName]
    if not targets then return false, "No destination for item: " .. itemName end

    for _, target in ipairs(targets) do
        if peripheral.isPresent(target) and getFreeSpace(target) > 0 then
            local moved = peripheral.wrap(chestName).pushItems(target, slot, count)
            if moved > 0 then
                return true, "Moved " .. moved .. "x " .. itemName .. " to " .. target
            end
        end
    end

    if overflowChest and peripheral.isPresent(overflowChest) then
        peripheral.wrap(chestName).pushItems(overflowChest, slot, count)
        return true, "Sent " .. itemName .. " to overflow"
    end

    return false, "No space for item: " .. itemName
end

-- Sort contents of a single chest
local function sortChest(chestName)
    if not peripheral.isPresent(chestName) then
        return false, "Chest not found: " .. chestName
    end

    local chest = peripheral.wrap(chestName)
    local contents = chest.list()
    local result = {}

    for slot, item in pairs(contents) do
        local success, message = moveItem(chestName, slot, item.name, item.count)
        table.insert(result, message)
    end

    return true, result
end

-- Server loop
while true do
    local senderId, msg, proto = rednet.receive(protocol)
    local reply = {}

    if type(msg) == "table" then
        for _, chestName in ipairs(msg) do
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
        table.insert(reply, "Invalid request: expected list of chests.")
    end

    rednet.send(senderId, reply, protocol)
end
