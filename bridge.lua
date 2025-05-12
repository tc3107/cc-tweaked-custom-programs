rednet.open('top')
rednet.open('bottom')
rednet.host('lookup', 'bridge')

while true do
    local id, msg, proto = rednet.receive()
    rednet.broadcast(msg, proto)
    print('Broadcasted: ', proto)
end
