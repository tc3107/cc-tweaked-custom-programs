print("Starting program...")

local relay = peripheral.wrap('redstone_relay_2')
rednet.open('left')
rednet.host('auth', 'airlock_control')

local authDict = {
    main_airlock = true
}

local function updateDict()
    authDict["main_airlock"] = relay.getInput('right')
end

while true do
    local id, msg, proto = rednet.receive()
    if proto == 'auth' then
        print("Request received from", id, "for:", msg)
        updateDict()
        
        if authDict[msg] == true then
            rednet.send(id, true, 'auth')
            print("Approved.")
        elseif authDict[msg] == false then
            rednet.send(id, false, 'auth')
            print("Denied.")
        else
            print("Not found.")
        end
    end
end
