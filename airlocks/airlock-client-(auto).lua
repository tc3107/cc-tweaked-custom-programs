local airlock_name = 'main_airlock'
--
print("Starting program...")

local monitor = peripheral.wrap("monitor_2")
local relay = peripheral.wrap("redstone_relay_4")
rednet.open('right')

term.redirect(monitor)
monitor.setTextScale(0.75)
monitor.clear()
monitor.setCursorPos(1,1)

print("Running control program...")

local doorState = false
local lastIn = false
local invert = true
local cycleTime = 2

local function update(state)
    if invert then
        state = not state
    end
    relay.setOutput('top', state)
end

update(doorState)

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
        print("Cycle starting - ", os.time())
        doorState = not doorState
        update(doorState)
        sleep(cycleTime)
        doorState = not doorState
        update(doorState)
        print("Cycle complete - ", os.time())
    end
end

while true do
    local leftIn = relay.getInput('right')
    local midIn = relay.getInput('front')
    
    if (leftIn or midIn) and not lastIn then
        switch()
    end
    lastIn = (leftIn or midIn)
    sleep(0.1)
end
