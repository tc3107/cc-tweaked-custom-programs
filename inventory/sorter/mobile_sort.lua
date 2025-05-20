-- mobile_sort_client.lua
local protocol = "sort"
local serverHostname = "inventory_control"

-- List of input chests to be sorted
local chestsToSort = {
    "minecraft:chest_31",
    "minecraft:barrel_11",
    "minecraft:chest_33"
    -- Add more chest IDs as needed
}

-- Open modem
rednet.open("back")  -- Change side if needed

-- Send the chest list
rednet.broadcast({chestsToSort}, protocol)
print("Sent sort request for chests:")
for _, name in ipairs(chestsToSort) do
    print("- " .. name)
end

print("Waiting for server updates...")

-- Receive and display every update until the server signals completion
while true do
    local senderId, data, proto = rednet.receive(protocol)
    local message = data[1]
    if proto == protocol then
        print("Server: " .. message)
        if message == "Sorting complete" then
            break
        end
    end
end
