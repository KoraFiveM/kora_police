-- Rob opens the target inventory (inspection grant, re-validated, revoked when
-- the target gets up / leaves) and drag has working release paths.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')

local policy
local closed = {}
handle.exportImpls.kora_inventory.registerInspectionAccess = function(cb) policy = cb; return 1 end
handle.exportImpls.kora_inventory.CloseInventory = function(src) closed[#closed + 1] = src; return true end

dofile('server/core.lua')
dofile('server/cuff.lua')
dofile('server/escort.lua')
dofile('server/seize.lua')
dofile('server/rob.lua')

local ROBBER, TARGET = 1, 2
local function reset()
    handle.addPlayer(ROBBER, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } }, money = { cash = 0, bank = 0 } })
    handle.addPlayer(TARGET, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } }, money = { cash = 100, bank = 0 }, metadata = { ishandcuffed = true } })
    Police.robGrants, Police.kidnapped, Police.escorted = {}, {}, {}
    for i = #closed, 1, -1 do closed[i] = nil end
    for k in pairs(Config.rob) do Config.rob[k] = nil end
    Config.rob.takeCash, Config.rob.openInventory, Config.rob.closeDistance, Config.rob.accessSeconds = true, true, 4.0, 120
end

h.test('civilians are denied inspection without a rob grant', function()
    reset()
    h.assertFalse(policy(ROBBER, TARGET) and true or false)
end)

h.test('rob takes cash, grants inspection and asks the robber client to open the inventory', function()
    reset()
    local ok, err, amount = Police.rob(ROBBER, TARGET)
    h.assertTrue(ok, tostring(err)); h.assertEqual(amount, 100)
    h.assertEqual(handle.players[ROBBER].data.money.cash, 100)
    local event = handle.lastClient('qbpolice:client:openRob')
    h.assertEqual(event.target, ROBBER); h.assertEqual(event.args[1], TARGET)
    h.assertTrue(policy(ROBBER, TARGET))
    h.assertFalse(policy(ROBBER, 99) and true or false)
end)

h.test('inventory-only rob works with no cash and with takeCash off', function()
    reset(); Config.rob.takeCash = false
    local ok, _, amount = Police.rob(ROBBER, TARGET)
    h.assertTrue(ok); h.assertEqual(amount, 0)
    h.assertEqual(handle.players[TARGET].data.money.cash, 100)
    reset(); handle.players[TARGET].data.money.cash = 0
    h.assertTrue(Police.rob(ROBBER, TARGET))
end)

h.test('openInventory off keeps the cash-only behaviour and grants nothing', function()
    reset(); Config.rob.openInventory = false
    h.assertTrue(Police.rob(ROBBER, TARGET))
    h.assertFalse(policy(ROBBER, TARGET) and true or false)
    handle.players[TARGET].data.money.cash = 0
    local ok, err = Police.rob(ROBBER, TARGET)
    h.assertFalse(ok); h.assertEqual(err, 'target has no cash')
    reset(); Config.rob.takeCash, Config.rob.openInventory = false, false
    h.assertFalse(Police.rob(ROBBER, TARGET))
end)

h.test('standing target cannot be robbed or inspected', function()
    reset(); handle.players[TARGET].data.metadata.ishandcuffed = false
    local ok, err = Police.rob(ROBBER, TARGET)
    h.assertFalse(ok); h.assertEqual(err, 'target is not restrained or down')
end)

h.test('grant is dropped and the inventory closed when the target gets up or walks away', function()
    reset(); Police.rob(ROBBER, TARGET)
    handle.eventHandlers['qbinventory:server:sessionOpened'][1](ROBBER, { secondary = { type = 'player' } })
    handle.setCoords(TARGET, 10.0, 0.0, 0.0)
    h.assertFalse(policy(ROBBER, TARGET) and true or false, 'out of range must be denied')
    Police.sweepRobGrants()
    h.assertEqual(closed[1], ROBBER); h.assertTrue(Police.robGrants[ROBBER] == nil)

    reset(); Police.rob(ROBBER, TARGET)
    handle.eventHandlers['qbinventory:server:sessionOpened'][1](ROBBER, { secondary = { type = 'player' } })
    handle.players[TARGET].data.metadata.ishandcuffed = false
    Police.sweepRobGrants()
    h.assertEqual(closed[1], ROBBER)
end)

h.test('grant expires', function()
    reset(); Config.rob.accessSeconds = 0
    Police.rob(ROBBER, TARGET)
    handle.advanceClock(100)
    h.assertFalse(policy(ROBBER, TARGET) and true or false)
end)

h.test('closing the session removes the grant', function()
    reset(); Police.rob(ROBBER, TARGET)
    handle.eventHandlers['qbinventory:server:sessionClosed'][1](ROBBER, {}, 'replaced')
    h.assertTrue(Police.robGrants[ROBBER] ~= nil, 'replaced must not drop the grant')
    handle.eventHandlers['qbinventory:server:sessionClosed'][1](ROBBER, {}, 'requested')
    h.assertTrue(Police.robGrants[ROBBER] == nil)
end)

h.test('drag sweep releases on distance, recovery and disconnect cleanup notifies both sides', function()
    reset()
    h.assertTrue(Police.startDrag(ROBBER, TARGET))
    Police.sweepDrags()
    h.assertEqual(Police.kidnapped[TARGET], ROBBER)
    handle.setCoords(TARGET, 50.0, 0.0, 0.0)
    Police.sweepDrags()
    h.assertTrue(Police.kidnapped[TARGET] == nil)
    h.assertTrue(handle.lastClient('qbpolice:client:dragStop').target == TARGET)
    h.assertTrue(handle.lastClient('qbpolice:client:dragStopSelf').target == ROBBER)

    reset(); Police.startDrag(ROBBER, TARGET)
    handle.players[TARGET].data.metadata.ishandcuffed = false
    Police.sweepDrags()
    h.assertTrue(Police.kidnapped[TARGET] == nil, 'recovered target is released')

    reset(); Police.startDrag(ROBBER, TARGET)
    local before = #handle.clientEvents
    handle.fireEvent('playerDropped', TARGET)
    h.assertTrue(#handle.clientEvents > before)
    h.assertEqual(handle.lastClient('qbpolice:client:dragStopSelf').target, ROBBER)
end)

h.test('only the dragger or dragged player can stop a drag', function()
    reset(); Police.startDrag(ROBBER, TARGET)
    local ok, err = Police.stopDrag(77, TARGET)
    h.assertFalse(ok); h.assertEqual(err, 'not authorised')
    h.assertTrue(Police.stopDrag(ROBBER, TARGET))
end)

h.test('client exposes a release command, key mapping and Release target while dragging', function()
    local f = assert(io.open('client/escort.lua', 'r')); local src = f:read('*a'); f:close()
    h.assertTrue(src:find("Kora.keybind.add", 1, true) ~= nil)
    h.assertTrue(src:find("label = 'Release'", 1, true) ~= nil)
    h.assertTrue(src:find("DetachEntity", 1, true) ~= nil)
    local r = assert(io.open('client/rob.lua', 'r')); local rs = r:read('*a'); r:close()
    h.assertTrue(rs:find("qbpolice:client:openRob", 1, true) ~= nil)
end)

h.test('stopDrag event falls back to the server-side target and resyncs a stale client', function()
    reset(); Police.startDrag(ROBBER, TARGET)
    handle.fireEvent('qbpolice:server:stopDrag', ROBBER, 999)
    h.assertTrue(Police.kidnapped[TARGET] == nil, 'wrong client target still releases the real one')
    handle.fireEvent('qbpolice:server:stopDrag', ROBBER, TARGET)
    h.assertEqual(handle.lastClient('qbpolice:client:dragStopSelf').target, ROBBER)
end)

h.test('release is silent when not dragging and the polled control is opt-in', function()
    local f = assert(io.open('client/escort.lua', 'r')); local src = f:read('*a'); f:close()
    h.assertTrue(src:find("You are not dragging anyone", 1, true) == nil)
    h.assertTrue(src:find("RegisterKeyMapping", 1, true) == nil, 'no global key mapping that fires on every press')
    h.assertEqual(Config.drag.releaseControl, 0, 'no per-frame poll by default')
end)

h.test('release key is a kora_lib keybind enabled only while dragging', function()
    local added, binding = nil, { disabledState = nil }
    function binding.disable(state) binding.disabledState = state; return true end
    local events, commands = {}, {}
    local env = setmetatable({
        Config = Config,
        Police = { notify = function() end, target = { reset = function() end, global = function() end } },
        Kora = { keybind = { add = function(options) added = options; return binding end } },
        RegisterNetEvent = function(name, fn) events[name] = fn end,
        RegisterCommand = function(name, fn) commands[name] = fn end,
        CreateThread = function() end,
        exports = setmetatable({}, { __index = function() return { getState = function() return { active = false } end } end }),
        GetGameTimer = function() return 100000 end,
    }, { __index = _G })
    local triggered = {}
    env.TriggerServerEvent = function(name, target) triggered[#triggered + 1] = { name = name, target = target } end
    local chunk = assert(loadfile('client/escort.lua', 't', env)); chunk()
    h.assertTrue(added ~= nil, 'keybind registered')
    h.assertEqual(added.defaultKey, Config.drag.releaseKey)
    h.assertTrue(added.disabled == true, 'disabled until a drag starts')
    added.onPressed(); h.assertEqual(#triggered, 0, 'pressing E while not dragging sends nothing')
    events['qbpolice:client:dragStartSelf'](5)
    h.assertTrue(binding.disabledState == false, 'enabled while dragging')
    added.onPressed()
    h.assertEqual(triggered[1].name, 'qbpolice:server:stopDrag'); h.assertEqual(triggered[1].target, 5)
    events['qbpolice:client:dragStopSelf']()
    h.assertTrue(binding.disabledState == true, 'disabled again once released')
    h.assertTrue(commands[Config.drag.releaseCommand] ~= nil, 'release command still registered')
end)

h.report('rob_inventory_drag_release')
