-- Source-level regression check: `/escort` must be able to end an escort
-- without requiring the officer to target the attached player behind them.
local h = dofile('test/harness.lua')

local file = assert(io.open('client/escort.lua', 'r'))
local source = file:read('*a')
file:close()

h.test('escort command releases the current escorted target', function()
    local command = assert(source:match("RegisterCommand%('escort'.-end, false%)"),
        'client escort command must be registered')
    h.assertTrue(command:find('Police%.escortedTarget') ~= nil,
        'escort command must inspect the active escorted target')
    h.assertTrue(command:find("qbpolice:server:deEscort") ~= nil,
        'escort command must send the server-validated stop event')
end)

h.report('escort_command')
