monitor = peripheral.wrap("monitor_1")
relay = peripheral.wrap("redstone_relay_1")

doorState = false
lastLeft = false
lastMid = false
lastRight = false

function switch()
    if doorState then
        doorState = false
    else
        doorState = true
    end
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

    relay.setOutput('top', doorState)
    sleep(0.1)
end
