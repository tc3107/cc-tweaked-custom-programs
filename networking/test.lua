local airlock_name = 'main_airlock'
local protocol = 'auth'
local server_name = 'airlock_control'

print("Starting airlock auth test...")

-- Open modem
rednet.open('right')

-- Attempt to locate the server
local serverId = rednet.lookup(protocol, server_name)
if not serverId then
    print("Error: Server '" .. server_name .. "' not found on protocol '" .. protocol .. "'.")
    return
end

-- Send a single auth request
print("Sending auth request as airlock:", airlock_name)
rednet.send(serverId, { airlock_name }, protocol)

-- Wait for response with timeout
local timeout = 5
local senderId, data, proto = rednet.receive(protocol, timeout)

-- Validate response
if senderId == serverId and type(data) == "table" and type(data[1]) == "boolean" then
    if data[1] == true then
        print("✅ Access granted.")
    else
        print("❌ Access denied.")
    end
else
    print("⚠️ No valid response received.")
    if type(data) == "table" then
        print("Raw message:", textutils.serialize(data))
    end
end
