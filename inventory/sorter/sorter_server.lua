-- inventory_control.lua (configurable via item_addresses.txt)

local protocol = "sort"
local hostname = "inventory_control"

-- Load mappings from configuration file
local destinationMap = {}
local overflowChest = nil

-- Simple trim utility
local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local protocol = "sort"
local hostname = "inventory_control"

-- Load mappings from configuration file
local destinationMap = {}
local overflowChest = nil

-- Simple trim utility
local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Read addresses from item_addresses.txt
if fs.exists("item_addresses.txt") then
    local file = fs.open("item_addresses.txt", "r")
    if file then
        local line = file.readLine()
        while line do
            line = trim(line)
            -- skip empty lines and comments
            if line ~= "" and not line:match("^#") then
                local key, val = line:match("([^=]+)=(.+)")
                if key and val then
                    key = trim(key)
                    val = trim(val)
                    if key == "overflowChest" then
                        overflowChest = val
                    else
                        local outputs = {}
                        for dest in val:gmatch("([^,]+)") do
                            table.insert(outputs, trim(dest))
                        end
                        destinationMap[key] = outputs
                    end
                end
            end
            line = file.readLine()
        end
        file.close()
        print("Configuration loaded from item_addresses.txt.")
    else
        error("Unable to open item_addresses.txt for reading.")
    end
else
    error("Configuration file 'item_addresses.txt' not found.")
end

-- Initialize networking
rednet.open("back") -- adjust side if needed
rednet.host(protocol, hostname)
print("Inventory server online as '" .. hostname .. "' using protocol '" .. protocol .. "'.")

-- Override print to also send every log line back to the client
local currentClientId
local originalPrint = print
print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[i] = tostring(select(i, ...))
    end
    local msg = table.concat(parts, " ")
    originalPrint(msg)
    if currentClientId then
        rednet.send(currentClientId, msg, protocol)
    end
end

-- Helper to check available space in a chest
local function getFreeSpace(chestName)
    if not peripheral.isPresent(chestName) then return -1 end
    local chest = peripheral.wrap(chestName)
    local total = chest.size()
    local used = 0
    for _, item in pairs(chest.list()) do
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
                    print("Moved " .. moved .. "x " .. itemName .. " to destination.")
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
    for slot, item in pairs(chest.list()) do
        local name  = item.name
        local count = item.count
        local targets = destinationMap[name]

        if targets then
            local success = moveItemToOutputs(chestName, slot, name, count, targets)
            if not success then
                if overflowChest and peripheral.isPresent(overflowChest) then
                    chest.pushItems(overflowChest, slot, count)
                    print("Moved " .. count .. "x " .. name .. " to overflow chest")
                else
                    print("Warning: No available space for " .. name .. " and no overflow defined")
                end
            end
        else
            print("Unmapped item: " .. name)
        end
    end
end

-- Main listener loop
while true do
    local senderId, msg, proto = rednet.receive(protocol)
    currentClientId = senderId

    if type(msg) == "table" then
        for _, chestName in ipairs(msg) do
            print("Sorting chest: " .. chestName)
            sortChest(chestName)
        end
    elseif type(msg) == "string" then
        print("Sorting single chest: " .. msg)
        sortChest(msg)
    else
        print("Invalid message format received")
    end

    print("Sorting complete")
    currentClientId = nil
end
