-- sort_client.lua
local protocol = "sort"
local serverHostname = "inventory_control"

local chestsToSort = {
    "chest_1",
    "chest_2"
    -- Add more chest IDs as needed
}

-- Open modem
rednet.open("right")

-- Lookup server
local serverId = rednet.lookup(protocol, serverHostname)
if not serverId then
    print("Error: Cannot find server '" .. serverHostname .. "' on protocol '" .. protocol .. "'.")
    return
end

-- Send sort request
rednet.send(serverId, chestsToSort, protocol)
print("Request sent to server...")

-- Wait for response
local timer = os.startTimer(5)
while true do
    local event, id, message = os.pullEvent()
    if event == "rednet_message" and id == serverId then
        print("Server response:")
        if type(message) == "table" then
            for _, line in ipairs(message) do
                print(line)
            end
        else
            print(message)
        end
        break
    elseif event == "timer" and id == timer then
        print("No response from server.")
        break
    end
end
