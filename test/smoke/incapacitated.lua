-- Police.isDowned / Police.isIncapacitated -- the shared rob/drag gate.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/cuff.lua')
dofile('server/escort.lua')
dofile('server/rob.lua')

local function reset(src)
    handle.players[src].data.metadata = {}
    handle.resourceStates.kora_ambulance = nil
    _G.Player = nil
    _G.GetEntityHealth = nil
    Config.incapacitated.downed, Config.incapacitated.cuffed = true, true
    Config.incapacitated.ambulance, Config.incapacitated.pedHealthFallback = true, false
end

local OFFICER, TARGET = 1, 2
handle.addPlayer(OFFICER, { job = { name = 'police', onduty = true, grade = { level = 1 } }, money = { cash = 0, bank = 0 } })
handle.addPlayer(TARGET, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } }, money = { cash = 100, bank = 0 } })

h.test('standing player is not incapacitated', function()
    reset(TARGET)
    h.assertFalse(Police.isIncapacitated(TARGET))
    local ok, err = Police.rob(OFFICER, TARGET)
    h.assertFalse(ok); h.assertEqual(err, 'target is not restrained or down')
end)

h.test('legacy metadata accepts true, 1 and "true"', function()
    for _, v in ipairs({ true, 1, 'true' }) do
        reset(TARGET)
        handle.players[TARGET].data.metadata.inlaststand = v
        h.assertTrue(Police.isIncapacitated(TARGET))
    end
    reset(TARGET)
    handle.players[TARGET].data.metadata.isdead = false
    h.assertFalse(Police.isIncapacitated(TARGET))
end)

h.test('kora_ambulance emsDown statebag counts when the resource is started', function()
    reset(TARGET)
    _G.Player = function() return { state = { emsDown = 'laststand' } } end
    h.assertFalse(Police.isIncapacitated(TARGET)) -- ambulance not started
    handle.resourceStates.kora_ambulance = 'started'
    h.assertTrue(Police.isIncapacitated(TARGET))
    _G.Player = function() return { state = { emsDown = false } } end
    h.assertFalse(Police.isIncapacitated(TARGET))
    Config.incapacitated.ambulance = false
    _G.Player = function() return { state = { emsDown = 'dead' } } end
    h.assertFalse(Police.isIncapacitated(TARGET))
end)

h.test('cuffed target is incapacitated and robbable', function()
    reset(TARGET)
    handle.players[TARGET].data.metadata.ishandcuffed = true
    h.assertTrue(Police.isIncapacitated(TARGET))
    Config.incapacitated.cuffed = false
    h.assertFalse(Police.isIncapacitated(TARGET))
end)

h.test('downed target can be robbed and dragged; config can disable downed', function()
    reset(TARGET)
    handle.players[TARGET].data.metadata.isdead = true
    local ok, err = Police.rob(OFFICER, TARGET)
    h.assertTrue(ok, tostring(err))
    local dragged, derr = Police.startDrag(OFFICER, TARGET)
    h.assertTrue(dragged, tostring(derr))
    Config.incapacitated.downed = false
    h.assertFalse(Police.isIncapacitated(TARGET))
end)

h.test('ped health fallback is opt-in', function()
    reset(TARGET)
    _G.GetEntityHealth = function() return 0 end
    h.assertFalse(Police.isIncapacitated(TARGET))
    Config.incapacitated.pedHealthFallback = true
    h.assertTrue(Police.isIncapacitated(TARGET))
end)

h.report('incapacitated')
