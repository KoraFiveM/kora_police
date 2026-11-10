-- Compatibility boundaries share the same server authority as the native
-- fingerprint and spike-strip routes.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/fingerprint.lua')
dofile('server/spikes.lua')
dofile('server/compat/police.lua')

local OFFICER, OTHER_OFFICER, TARGET, CIVILIAN = 1, 2, 3, 4
local policeJob = { name = 'police', onduty = true, grade = { level = 1 } }

handle.addPlayer(OFFICER, { job = policeJob })
handle.addPlayer(OTHER_OFFICER, { job = { name = 'police', onduty = true, grade = { level = 1 } } })
handle.addPlayer(TARGET)
handle.addPlayer(CIVILIAN)
handle.setCoords(OFFICER, 0.0, 0.0, 0.0)
handle.setCoords(OTHER_OFFICER, 0.0, 0.0, 0.0)
handle.setCoords(TARGET, 0.0, 0.0, 0.0)
handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0)

h.test('fingerprint callback requires an on-duty officer and a cuffed nearby target', function()
    local callback = handle.Kora.callback.registry['kora_police:server:getFingerprint']
    h.assertTrue(callback ~= nil)
    h.assertEqual(callback(CIVILIAN, TARGET), nil)
    h.assertEqual(callback(OFFICER, TARGET), nil)

    handle.players[TARGET].data.metadata.ishandcuffed = true
    local fingerprint = callback(OFFICER, TARGET)
    h.assertTrue(type(fingerprint) == 'string' and #fingerprint > 0)

    handle.setCoords(TARGET, 100.0, 0.0, 0.0)
    h.assertEqual(callback(OFFICER, TARGET), nil)
    handle.setCoords(TARGET, 0.0, 0.0, 0.0)
end)

h.test('legacy fingerprint events use the same guarded lookup', function()
    local before = #handle.clientEventsFor('police:client:showFingerprint')
    handle.fireEvent('police:server:showFingerprint', CIVILIAN, TARGET)
    h.assertEqual(#handle.clientEventsFor('police:client:showFingerprint'), before)

    handle.fireEvent('police:server:showFingerprint', OFFICER, TARGET)
    local event = handle.lastClient('police:client:showFingerprint')
    h.assertTrue(event ~= nil)
    h.assertEqual(event.target, OFFICER)
end)

h.test('spike deployment rejects malformed and remote coordinates', function()
    h.assertFalse((Police.deploySpike(OFFICER, { x = 0 / 0, y = 0.0, z = 0.0 })))
    h.assertFalse((Police.deploySpike(OFFICER, { x = 100.0, y = 0.0, z = 0.0 })))
    h.assertFalse((Police.deploySpike(CIVILIAN, { x = 1.0, y = 0.0, z = 0.0 })))
end)

h.test('legacy spike sync only lets the owning officer remove a tracked strip', function()
    local netId = Police.deploySpike(OFFICER, { x = 2.0, y = 0.0, z = 0.0 })
    h.assertTrue(type(netId) == 'number')

    handle.fireEvent('police:server:SyncSpikes', OTHER_OFFICER, netId, false)
    h.assertTrue(Police.spikes[netId] ~= nil)

    handle.fireEvent('police:server:SyncSpikes', OFFICER, netId, true)
    h.assertTrue(Police.spikes[netId] ~= nil)

    local before = #handle.clientEventsFor('police:client:SyncSpikes')
    handle.fireEvent('police:server:SyncSpikes', OFFICER, netId, false)
    h.assertEqual(Police.spikes[netId], nil)
    h.assertEqual(#handle.clientEventsFor('police:client:SyncSpikes'), before + 1)
end)

h.report('compat_boundaries')
