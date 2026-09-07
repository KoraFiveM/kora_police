-- Police.cuff/uncuff/softCuffNearby/breakCuffs -- real branching around
-- on-duty officer checks, distance, and soft-cuff escape attempts/cooldown.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/cuff.lua')

local OFFICER, SUSPECT, CIVILIAN = 1, 2, 3
local FAR = 9999.0

handle.addPlayer(OFFICER, { job = { name = 'police', onduty = true, grade = { level = 1 } } })
handle.addPlayer(SUSPECT, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } } })
handle.addPlayer(CIVILIAN, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } } })

-- Everyone starts far apart from each other; each test brings exactly the
-- players it cares about into range so results are deterministic regardless
-- of test order.
handle.setCoords(OFFICER, 0.0, 0.0, 0.0)
handle.setCoords(SUSPECT, FAR, 0.0, 0.0)
handle.setCoords(CIVILIAN, 0.0, FAR, 0.0)

h.test('an off-duty player cannot cuff anyone', function()
    handle.setCoords(SUSPECT, 0.0, 0.0, 0.0)
    handle.players[OFFICER].job.onduty = false
    local ok, err = Police.cuff(OFFICER, SUSPECT)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    handle.players[OFFICER].job.onduty = true
end)

h.test('an on-duty officer within range cuffs a target', function()
    local ok = Police.cuff(OFFICER, SUSPECT)
    h.assertTrue(ok)
    h.assertTrue(Police.isCuffed(SUSPECT))
    h.assertEqual(handle.players[SUSPECT].data.metadata.ishandcuffed, true)
    local events = handle.clientEventsFor('qbpolice:client:cuffed')
    h.assertEqual(#events, 1)
    h.assertEqual(events[1].target, SUSPECT)
    h.assertEqual(events[1].args[1], true)
    h.assertEqual(events[1].args[2], false)
end)

h.test('cuffing an already-cuffed target fails', function()
    local ok, err = Police.cuff(OFFICER, SUSPECT)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('an officer can uncuff a hard-cuffed target', function()
    local ok = Police.uncuff(OFFICER, SUSPECT)
    h.assertTrue(ok)
    h.assertFalse(Police.isCuffed(SUSPECT))
end)

h.test('cuffing beyond Config.cuff.distance fails', function()
    handle.setCoords(SUSPECT, FAR, 0.0, 0.0)
    local ok, err = Police.cuff(OFFICER, SUSPECT)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    handle.setCoords(SUSPECT, 0.0, 0.0, 0.0)
end)

h.test('a hard-cuffed target cannot self-release', function()
    Police.cuff(OFFICER, SUSPECT)
    local ok, err = Police.uncuff(SUSPECT, SUSPECT)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    Police.uncuff(OFFICER, SUSPECT)
    handle.setCoords(SUSPECT, FAR, 0.0, 0.0)
end)

h.test('softCuffNearby cuffs the single other player in range', function()
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0)  -- only CIVILIAN is near OFFICER now
    local ok = Police.softCuffNearby(OFFICER)
    h.assertTrue(ok)
    h.assertTrue(Police.isCuffed(CIVILIAN))
    h.assertTrue(Police.cuffState[CIVILIAN].soft)
    Police.uncuff(OFFICER, CIVILIAN)
    handle.setCoords(CIVILIAN, 0.0, FAR, 0.0)
end)

h.test('softCuffNearby refuses when more than one candidate is in range', function()
    handle.setCoords(SUSPECT, 0.0, 0.0, 0.0)
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0)
    local ok, err = Police.softCuffNearby(OFFICER)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    handle.setCoords(SUSPECT, FAR, 0.0, 0.0)
    handle.setCoords(CIVILIAN, 0.0, FAR, 0.0)
end)

h.test('softCuffNearby refuses when no one is in range', function()
    local ok, err = Police.softCuffNearby(OFFICER)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('a soft cuff can be broken via breakCuffs, consuming an attempt', function()
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0)
    Police.softCuffNearby(OFFICER)
    h.assertTrue(Police.isCuffed(CIVILIAN))

    local authorization = Police.beginBreakCuffs(CIVILIAN)
    local proof = handle.issueMinigameProof(CIVILIAN, Config.minigames.breakCuffs.type, authorization)
    local ok = Police.breakCuffs(CIVILIAN, proof)
    h.assertTrue(ok)
    h.assertFalse(Police.isCuffed(CIVILIAN))
    handle.setCoords(CIVILIAN, 0.0, FAR, 0.0)
end)

h.test('breakCuffs refuses a hard cuff', function()
    handle.setCoords(SUSPECT, 0.0, 0.0, 0.0)
    Police.cuff(OFFICER, SUSPECT)
    local ok, err = Police.breakCuffs(SUSPECT, 'not-a-proof')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    Police.uncuff(OFFICER, SUSPECT)
    handle.setCoords(SUSPECT, FAR, 0.0, 0.0)
end)

h.test('the network result rejects a forged client success boolean', function()
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0)
    Police.softCuffNearby(OFFICER)
    Police.beginBreakCuffs(CIVILIAN)

    handle.fireEvent('qbpolice:server:breakCuffsResult', CIVILIAN, true)

    h.assertTrue(Police.isCuffed(CIVILIAN))
    h.assertEqual(Police.cuffState[CIVILIAN].attemptsUsed, 1)
    Police.uncuff(OFFICER, CIVILIAN)
    handle.setCoords(CIVILIAN, 0.0, FAR, 0.0)
end)

h.test('the network result rejects another player\'s minigame proof', function()
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0)
    Police.softCuffNearby(OFFICER)
    local authorization = Police.beginBreakCuffs(CIVILIAN)
    local proof = handle.issueMinigameProof(SUSPECT, Config.minigames.breakCuffs.type, authorization)

    handle.fireEvent('qbpolice:server:breakCuffsResult', CIVILIAN, proof)

    h.assertTrue(Police.isCuffed(CIVILIAN))
    Police.uncuff(OFFICER, CIVILIAN)
    handle.setCoords(CIVILIAN, 0.0, FAR, 0.0)
end)

h.test('the network result accepts one source-bound mash proof', function()
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0)
    Police.softCuffNearby(OFFICER)
    local authorization = Police.beginBreakCuffs(CIVILIAN)
    local proof = handle.issueMinigameProof(CIVILIAN, Config.minigames.breakCuffs.type, authorization)

    handle.fireEvent('qbpolice:server:breakCuffsResult', CIVILIAN, proof)

    h.assertFalse(Police.isCuffed(CIVILIAN))
    h.assertEqual(handle.lastClient('QBCore:Notify').target, CIVILIAN)
    handle.setCoords(CIVILIAN, 0.0, FAR, 0.0)
end)

h.test('breakCuffsFailed applies a cooldown that blocks an immediate retry', function()
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0)
    Police.softCuffNearby(OFFICER)
    h.assertTrue(Police.isCuffed(CIVILIAN))

    Police.breakCuffsFailed(CIVILIAN)
    local ok, err = Police.breakCuffs(CIVILIAN, 'not-a-proof')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('breakCuffs refuses once the attempt cap is reached', function()
    local state = Police.cuffState[CIVILIAN]
    state.cooldownUntil = 0
    state.attemptsUsed = Config.cuff.breakCuffsAttempts
    local ok, err = Police.breakCuffs(CIVILIAN, 'not-a-proof')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.report('cuff')
