-- qb-policejob parity: stock callback names/shapes, policeAlert, cop-count
-- payloads, FlaggedPlateTriggered(coords, plate) and SetHandcuffStatus(bool).
-- Every stock path must still go through kora's own checks.
local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install()
dofile('config.lua')
local hashes = { WEAPON_SMG = 700000, COMPONENT_AT_PI_SUPP = 300 }
_G.joaat = function(v) return hashes[v:upper()] or 999 end
dofile('server/core.lua')
dofile('server/cuff.lua')
dofile('server/escort.lua')
dofile('server/plate_flag.lua')
dofile('server/dispatch.lua')
dofile('server/callbacks.lua')
dofile('server/compat/police.lua')

local OFFICER, CHIEF, OFFDUTY, TARGET, CIVILIAN, FAR = 1, 2, 3, 4, 5, 6
handle.addPlayer(OFFICER, { job = { name = 'police', onduty = true, grade = { level = 1 } } })
handle.addPlayer(CHIEF, { job = { name = 'police', onduty = true, grade = { level = 3 } } })
handle.addPlayer(OFFDUTY, { job = { name = 'police', onduty = false, grade = { level = 4 } } })
handle.addPlayer(TARGET)
handle.addPlayer(CIVILIAN)
handle.addPlayer(FAR)
handle.setCoords(FAR, 500.0, 0.0, 0.0)
handle.players[CHIEF].data.metadata.callsign = 'A-1'
local cb = handle.Kora.callback.registry

h.test('GetCops returns the on-duty LEO count to any caller', function()
    h.assertEqual(cb['police:GetCops'](CIVILIAN), 2)
    h.assertEqual(cb['police:GetCops'](OFFICER), 2)
end)

h.test('the old list form lives under a kora name and stays police-only', function()
    local list = cb['kora_police:server:getCops'](OFFICER)
    h.assertEqual(#list, 2)
    h.assertEqual(#cb['kora_police:server:getCops'](CIVILIAN), 0)
end)

h.test('GetDutyPlayers is open to civilians with the stock shape and no identity', function()
    local list = cb['police:GetDutyPlayers'](CIVILIAN)
    h.assertEqual(#list, 2)
    h.assertEqual(list[2].source, CHIEF)
    h.assertEqual(list[2].label, 'A-1')
    h.assertEqual(list[2].job, 'police')
    h.assertEqual(list[2].citizenid, nil)
    h.assertTrue(cb['police:GetDutyPlayers'](OFFICER)[1].citizenid ~= nil)
end)

h.test('stock-named callbacks exist', function()
    for _, name in ipairs({ 'police:server:isPlayerDead', 'police:server:IsPoliceForcePresent',
        'police:server:IsPlateFlagged', 'police:IsSilencedWeapon' }) do
        h.assertTrue(cb[name] ~= nil, name)
    end
end)

h.test('IsPoliceForcePresent needs an on-duty grade 2+ officer, for any caller', function()
    h.assertTrue(cb['police:server:IsPoliceForcePresent'](CIVILIAN))
    handle.players[CHIEF].job.onduty = false
    h.assertFalse(cb['police:server:IsPoliceForcePresent'](CIVILIAN))
    handle.players[CHIEF].job.onduty = true
end)

h.test('isPlayerDead: civilians only see themselves or someone within reach', function()
    handle.players[TARGET].data.metadata.isdead = true
    h.assertTrue(cb['police:server:isPlayerDead'](CIVILIAN, TARGET))
    h.assertFalse(cb['police:server:isPlayerDead'](CIVILIAN, FAR))
    handle.players[FAR].data.metadata.isdead = true
    h.assertFalse(cb['police:server:isPlayerDead'](CIVILIAN, FAR))
    h.assertTrue(cb['police:server:isPlayerDead'](OFFICER, FAR))
    handle.players[TARGET].data.metadata.isdead = nil
end)

h.test('IsPlateFlagged alias is officer-only like the native callback', function()
    Police.flagPlate(OFFICER, 'STOCK1', 'bolo')
    h.assertTrue(cb['police:server:IsPlateFlagged'](OFFICER, 'stock1'))
    h.assertFalse(cb['police:server:IsPlateFlagged'](CIVILIAN, 'STOCK1'))
end)

h.test('IsSilencedWeapon takes a weapon hash/name and checks the caller\'s own gun', function()
    local selected = 700000
    _G.GetSelectedPedWeapon = function() return selected end
    handle.exportImpls.kora_inventory.GetEquippedWeapon = function()
        return { name = 'weapon_smg', components = { 'COMPONENT_AT_PI_SUPP' } }
    end
    h.assertTrue(cb['police:IsSilencedWeapon'](CIVILIAN, 700000))
    h.assertTrue(cb['police:IsSilencedWeapon'](CIVILIAN, 'weapon_smg'))
    h.assertFalse(cb['police:IsSilencedWeapon'](CIVILIAN, 123456), 'a different weapon is not the held one')
    selected = 1
    h.assertFalse(cb['police:IsSilencedWeapon'](CIVILIAN, 700000), 'the weapon must be the selected one')
    -- the older target form is still police-only
    selected = 700000
    h.assertFalse(cb['police:IsSilencedWeapon'](CIVILIAN, TARGET))
    h.assertTrue(cb['police:IsSilencedWeapon'](OFFICER, TARGET))
end)

h.test('cop count is broadcast to everyone as police:SetCopCount with a bare number', function()
    Police.broadcastCopCount()
    local event = handle.lastClient('police:SetCopCount')
    h.assertTrue(event ~= nil)
    h.assertEqual(event.target, -1)
    h.assertEqual(event.args[1], 2)
end)

h.test('UpdateCurrentCops from a client is throttled', function()
    local before = #handle.clientEventsFor('police:SetCopCount')
    handle.fireEvent('police:server:UpdateCurrentCops', CIVILIAN)
    handle.fireEvent('police:server:UpdateCurrentCops', CIVILIAN)
    handle.fireEvent('police:server:UpdateBlips', CIVILIAN)
    h.assertEqual(#handle.clientEventsFor('police:SetCopCount'), before + 1)
end)

h.test('the cop-count throttle is per source', function()
    handle.advanceClock(Config.dispatch.copCountThrottle + 1)
    local before = #handle.clientEventsFor('police:SetCopCount')
    handle.fireEvent('police:server:UpdateCurrentCops', CIVILIAN)
    handle.fireEvent('police:server:UpdateCurrentCops', CIVILIAN)
    handle.fireEvent('police:server:SetCopCount', TARGET)
    handle.fireEvent('police:server:SetCopCount', TARGET)
    h.assertEqual(#handle.clientEventsFor('police:SetCopCount'), before + 2)
end)

h.test('SetHandcuffStatus(bool) never changes cuff state', function()
    handle.fireEvent('police:server:SetHandcuffStatus', CIVILIAN, true)
    h.assertFalse(Police.isCuffed(CIVILIAN))
    h.assertFalse(Police.isCuffed(OFFICER))
    handle.fireEvent('police:server:SetHandcuffStatus', OFFICER, true)
    h.assertFalse(Police.isCuffed(OFFICER))
    -- an unescapable officer cuff cannot be shed by claiming `false`
    h.assertTrue(Police.cuff(OFFICER, TARGET))
    handle.fireEvent('police:server:SetHandcuffStatus', TARGET, false)
    h.assertTrue(Police.isCuffed(TARGET))
    local sync = handle.lastClient('kora_police:client:cuffed')
    h.assertEqual(sync.target, TARGET)
    h.assertEqual(sync.args[1], true)
    h.assertTrue(Police.uncuff(OFFICER, TARGET))
end)

h.test('SetHandcuffStatus(target, cuffed) keeps the officer checks', function()
    handle.fireEvent('police:server:SetHandcuffStatus', CIVILIAN, TARGET, true)
    h.assertFalse(Police.isCuffed(TARGET))
    handle.fireEvent('police:server:SetHandcuffStatus', OFFICER, TARGET, true)
    h.assertTrue(Police.isCuffed(TARGET))
    Police.uncuff(OFFICER, TARGET)
end)

h.test('CuffPlayer(target, isSoftcuff) still requires an officer in reach', function()
    handle.fireEvent('police:server:CuffPlayer', CIVILIAN, TARGET, true)
    h.assertFalse(Police.isCuffed(TARGET))
    handle.fireEvent('police:server:CuffPlayer', OFFICER, FAR, true)
    h.assertFalse(Police.isCuffed(FAR))
    handle.fireEvent('police:server:CuffPlayer', OFFICER, TARGET, true)
    h.assertTrue(Police.isCuffed(TARGET))
    h.assertFalse(Police.cuffState[TARGET].soft, 'an officer cuff is never the escapable kind')
    Police.uncuff(OFFICER, TARGET)
end)

h.test('FlaggedPlateTriggered takes (coords, plate), validates and alerts officers only', function()
    local coords = { x = 1.0, y = 2.0, z = 3.0 }
    local before = #handle.clientEventsFor('police:client:FlaggedPlateTriggered')
    handle.fireEvent('police:server:FlaggedPlateTriggered', CIVILIAN, coords, 'STOCK1')
    h.assertEqual(#handle.clientEventsFor('police:client:FlaggedPlateTriggered'), before, 'civilians cannot raise it')
    handle.fireEvent('police:server:FlaggedPlateTriggered', OFFICER, coords, 'NOTFLAGGED')
    h.assertEqual(#handle.clientEventsFor('police:client:FlaggedPlateTriggered'), before, 'unflagged plates raise nothing')
    handle.advanceClock(2000)
    handle.fireEvent('police:server:FlaggedPlateTriggered', OFFICER, coords, 'stock1')
    local event = handle.lastClient('police:client:FlaggedPlateTriggered')
    h.assertTrue(event ~= nil)
    h.assertEqual(event.args[1], 'STOCK1')
    h.assertEqual(event.args[2], 'bolo')
    handle.advanceClock(2000)
    local count = #handle.clientEventsFor('police:client:FlaggedPlateTriggered')
    handle.fireEvent('police:server:FlaggedPlateTriggered', OFFICER, { x = 1 }, { not_a_plate = true })
    h.assertEqual(#handle.clientEventsFor('police:client:FlaggedPlateTriggered'), count, 'a non-string plate is ignored')
end)

h.test('policeAlert raises one validated call at the caller\'s own position', function()
    handle.setCoords(CIVILIAN, 10.0, 20.0, 30.0)
    local before = #handle.dispatchCalls
    handle.fireEvent('police:server:policeAlert', CIVILIAN, 'Suspicious \n person   ')
    h.assertEqual(#handle.dispatchCalls, before + 1)
    local call = handle.lastDispatchCall()
    h.assertEqual(call.message, 'Suspicious   person')
    h.assertEqual(call.coords.x, 10.0)
    h.assertEqual(call.jobTypes[1], Config.police.jobType)
end)

h.test('policeAlert is rate limited and rejects bad input', function()
    local before = #handle.dispatchCalls
    handle.fireEvent('police:server:policeAlert', CIVILIAN, 'again')
    h.assertEqual(#handle.dispatchCalls, before, 'second call inside the cooldown is dropped')
    handle.advanceClock(Config.dispatch.legacyAlertCooldown + 1)
    handle.fireEvent('police:server:policeAlert', CIVILIAN, { text = 'table' })
    handle.fireEvent('police:server:policeAlert', CIVILIAN, '   ')
    handle.fireEvent('police:server:policeAlert', nil, 'no source')
    h.assertEqual(#handle.dispatchCalls, before)
    handle.fireEvent('police:server:policeAlert', CIVILIAN, string.rep('x', 500))
    h.assertEqual(#handle.lastDispatchCall().message, Config.dispatch.legacyAlertMaxLength)
end)

h.test('policeAlert ignores kora_core\'s local mirror even when it carries a player source', function()
    handle.advanceClock(Config.dispatch.legacyAlertCooldown + 1)
    local before = #handle.dispatchCalls
    -- Core.dispatch.alert order: server mirror event, then the legacy local event.
    local previous = _G.source
    _G.source = TARGET
    _G.TriggerEvent('kora_core:server:dispatchAlert', { jobs = { 'police' }, message = 'Shop robbery' }, 1)
    _G.TriggerEvent('police:server:policeAlert', 'Shop robbery')
    _G.source = previous
    h.assertEqual(#handle.dispatchCalls, before, 'mirror must not raise a duplicate call')
    -- The mirror is consumed once: the same text from a real client then works.
    handle.fireEvent('police:server:policeAlert', TARGET, 'Shop robbery')
    h.assertEqual(#handle.dispatchCalls, before + 1)
end)

h.test('PutPlayerInVehicle(target) alone picks the nearest vehicle but keeps the cuff check', function()
    _G.GetAllVehicles = function() return { 7 } end
    _G.GetEntityCoords = (function(orig)
        return function(e) if e == 7 then return handle.vec3(1.0, 0.0, 0.0) end return orig(e) end
    end)(_G.GetEntityCoords)
    local exists = _G.DoesEntityExist
    _G.DoesEntityExist = function(e) return e == 7 or exists(e) end
    _G.NetworkGetEntityFromNetworkId = function(netId) return netId - 1000 end
    local before = #handle.clientEventsFor('kora_police:client:putInVehicle')
    handle.fireEvent('police:server:PutPlayerInVehicle', OFFICER, TARGET)
    h.assertEqual(#handle.clientEventsFor('kora_police:client:putInVehicle'), before, 'uncuffed target is refused')
    Police.cuff(OFFICER, TARGET)
    handle.fireEvent('police:server:PutPlayerInVehicle', OFFICER, TARGET)
    local event = handle.lastClient('kora_police:client:putInVehicle')
    h.assertEqual(#handle.clientEventsFor('kora_police:client:putInVehicle'), before + 1)
    h.assertEqual(event.args[1], 1007)
end)

h.report('stock_parity')
