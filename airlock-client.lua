monitor = peripheral.wrap("monitor_1")
relay = peripheral.wrap("redstone_relay_1")

term.redirect(monitor)
monitor.setTextScale(1)
monitor.clear()
monitor.setCursorPos(1,1)

print("Running control program...")

doorState = false
lastLeft = false
lastMid = false
lastRight = false

function switch()
    if doorState then
        doorState = false
        print("Airlock Position A - ", os.time())
    else
        doorState = true
        print("Airlock Position B - ", os.time())
    end

    print("Switched Airlock State")
end

while true do
    leftIn = relay.getInput('right')
    midIn = relay.getInput('front')
    rightIn = relay.getInput('left')
    
    if leftIn then
        if lastLeft == false then
            switch()
        end
        lastLeft = true
    else
        lastLeft = false
    end

    if midIn then
        if lastMid == false then
            switch()
        end
        lastMid = true
    else
        lastMid = false
    end

    if rightIn then
        if lastRight == false then
            switch()
        end
        lastRight = true
    else
        lastRight = false
    end
    
    relay.setOutput('top', doorState)
    sleep(0.1)
end
