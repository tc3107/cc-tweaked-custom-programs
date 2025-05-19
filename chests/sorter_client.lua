-- sort_client.lua
local protocol = "sort"
local serverHostname = "inventory_control"

-- List of input chests to be sorted
local chestsToSort = {
    "chest_1",
    "chest_2"
    -- Add more chest IDs as needed
}

-- Open modem
rednet.open("back")  -- Change side if needed

-- Lookup the server by hostname
local serverId = rednet.lookup(protocol, serverHostname)
if not serverId then
    print("Error: Could not find server '" .. serverHostname .. "' on protocol '" .. protocol .. "'.")
    return
end

-- Send the chest list
rednet.send(serverId, chestsToSort, protocol)
print("Sent sort request to server for chests:")
for _, name in ipairs(chestsToSort) do
    print("- " .. name)
end

-- Optionally wait for an acknowledgment
local timer = os.startTimer(3)  -- Wait up to 3 seconds
while true do
    local event, p1, p2, p3 = os.pullEvent()
    if event == "rednet_message" and p1 == serverId then
        print("Server replied: " .. tostring(p2))
        break
    elseif event == "timer" and p1 == timer then
        print("No reply from server, continuing anyway.")
        break
    end
end
