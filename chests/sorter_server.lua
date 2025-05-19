-- inventory_control.lua
local protocol = "sort"
local hostname = "inventory_control"

-- Map of item names to list of destination chest peripheral names
local destinationMap = {
    ["minecraft:cobblestone"] = { "chest1", "chest2", "chest3" },
    ["minecraft:iron_ingot"] = { "chest0" }
    -- Add more mappings here
}

-- Optional overflow chest
local overflowChest = "chest_overflow"

-- Initialize networking
rednet.open("top") -- adjust side if needed
rednet.host(protocol, hostname)
print("Inventory server online as '" .. hostname .. "' using protocol '" .. protocol .. "'.")

-- Helper to check available space in a chest
local function getFreeSpace(chestName)
    if not peripheral.isPresent(chestName) then return -1 end
    local chest = peripheral.wrap(chestName)
    local total = chest.size()
    local used = 0
    for slot, item in pairs(chest.list()) do
        if item then used = used + 1 end
    end
    return total - used
end

-- Try to move item to one of the output chests in the list
local function moveItemToOutputs(src, slot, itemName, amount, outputs)
    for _, destName in ipairs(outputs) do
        if peripheral.isPresent(destName) then
            local free = getFreeSpace(destName)
            if free > 0 then
                local moved = peripheral.wrap(src).pushItems(destName, slot, amount)
                if moved > 0 then
                    print("Moved " .. moved .. "x " .. itemName .. " from " .. src .. " to " .. destName)
                    return true
                end
            end
        end
    end
    return false
end

-- Sort items from a single input chest
local function sortChest(chestName)
    if not peripheral.isPresent(chestName) then
        print("Error: Chest '" .. chestName .. "' not found.")
        return
    end

    local chest = peripheral.wrap(chestName)
    local items = chest.list()

    for slot, item in pairs(items) do
        local name = item.name
        local count = item.count
        local targets = destinationMap[name]

        if targets then
            local success = moveItemToOutputs(chestName, slot, name, count, targets)
            if not success and overflowChest and peripheral.isPresent(overflowChest) then
                chest.pushItems(overflowChest, slot, count)
                print("Moved " .. count .. "x " .. name .. " to overflow chest.")
            elseif not success then
                print("Warning: No available space for " .. name .. ", and no overflow defined.")
            end
        else
            print("Unmapped item: " .. name)
        end
    end
end

-- Main listener loop
while true do
    local senderId, msg, proto = rednet.receive(protocol)
    if type(msg) == "table" then
        for _, chestName in ipairs(msg) do
            print("Sorting chest: " .. chestName)
            sortChest(chestName)
        end
    elseif type(msg) == "string" then
        print("Sorting single chest: " .. msg)
        sortChest(msg)
    else
        print("Invalid message format received.")
    end
end
