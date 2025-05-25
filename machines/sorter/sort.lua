-- sort_client.lua
local protocol = "sort"
local serverHostname = "inventory_control"

-- List of input chests to be sorted
local chestsToSort = {
    "minecraft:chest_0"
    -- Add more chest IDs as needed
}

-- Open modem
rednet.open("right")  -- Change side if needed

-- Lookup the server by hostname
local serverId = rednet.lookup(protocol, serverHostname)
if not serverId then
    print("Error: Could not find server '" .. serverHostname .. "' on protocol '" .. protocol .. "'.")
    return
end

-- Send the chest list
rednet.send(serverId, {chestsToSort}, protocol)
print("Sent sort request for chests:")
for _, name in ipairs(chestsToSort) do
    print("- " .. name)
end

print("Waiting for server updates...")

-- Receive and display every update until the server signals completion
while true do
    local senderId, data, proto = rednet.receive(protocol)
    local message = type(data)=='table' and data[1]
    if senderId == serverId and message ~= nil then
        print("Server: " .. message)
        if message == "Sorting complete" then
            break
        end
    else
        print("Received malformed message from " .. senderId)
    end
end
