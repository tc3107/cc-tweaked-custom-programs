-- Scrollable Peripheral List

local peripherals = peripheral.getNames()
local lines = {}

-- Build the lines to display
table.insert(lines, "Attached peripherals:")
for i, name in ipairs(peripherals) do
    table.insert(lines, i .. ": " .. name)
end

-- Initialize scroll state
local scroll = 0
local height = term.getSize()

-- Function to redraw the screen
local function redraw()
    term.clear()
    term.setCursorPos(1, 1)
    for i = 1, height do
        local lineIndex = i + scroll
        if lines[lineIndex] then
            print(lines[lineIndex])
        end
    end
end

-- Initial draw
redraw()

-- Main event loop to handle scrolling
while true do
    local event, direction = os.pullEvent()
    if event == "mouse_scroll" then
        if direction == -1 and scroll > 0 then
            scroll = scroll - 1
        elseif direction == 1 and (scroll + height) < #lines then
            scroll = scroll + 1
        end
        redraw()
    elseif event == "key" and direction == keys.q then
        -- Optional: press Q to quit
        break
    end
end
