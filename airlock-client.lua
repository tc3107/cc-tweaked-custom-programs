local airlock_name = 'main_airlock'

print("Starting program...")
relay.setOutput('top', doorState)

local monitor = peripheral.wrap("monitor_1")
local relay = peripheral.wrap("redstone_relay_1")
rednet.open('right')

term.redirect(monitor)
monitor.setTextScale(0.75)
monitor.clear()
monitor.setCursorPos(1,1)

print("Running control program...")

local doorState = false
local lastLeft = false
local lastMid = false
local lastRight = false

local function request()
    local server = rednet.lookup('auth', 'airlock_control')
    if server then
        print("Sending request...")
        rednet.send(server, airlock_name, 'auth')
        local id, msg, proto = rednet.receive('auth', 5)
        if id == server and type(msg) == 'boolean' then
            if msg == true then
                print("Request approved.")
                return true
            elseif msg == false then
                print("Request denied.")
                return false
            end
        else
            print("No valid response.")
        end
    else
        print("No server found.")
    end
    return false
end

local function switch()
    if request() then
        doorState = not doorState
        if doorState then
            print("Airlock Position B - ", os.time())
        else
            print("Airlock Position A - ", os.time())
        end
    end
end

while true do
    local leftIn = relay.getInput('right')
    local midIn = relay.getInput('front')
    local rightIn = relay.getInput('left')
    
    if leftIn and not lastLeft then
        switch()
    end
    lastLeft = leftIn

    if midIn and not lastMid then
        switch()
    end
    lastMid = midIn

    if rightIn and not lastRight then
        switch()
    end
    lastRight = rightIn
    
    relay.setOutput('top', doorState)
    sleep(0.1)
end
