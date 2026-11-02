-- Police.cuff/uncuff/softCuffNearby/breakCuffs -- real branching around
-- on-duty officer checks, distance, and soft-cuff escape attempts/cooldown.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
local useables = {}
handle.exportImpls.kora_core.createUseable = function(name, callback) useables[name] = callback end
handle.exportImpls.kora_core.hasItem = function(src, name)
    for _, item in pairs(handle.players[src] and handle.players[src].data.items or {}) do
        if item.name == name and item.amount >= 1 then return true end
    end
    return false
end
dofile(arg[1] or 'server/cuff.lua')
dofile('server/compat/police.lua')
dofile('server/escort.lua')

local OFFICER, SUSPECT, CIVILIAN = 1, 2, 3
local FAR = 9999.0

handle.addPlayer(OFFICER, { job = { name = 'police', onduty = true, grade = { level = 1 } } })
handle.addPlayer(SUSPECT, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } } })
handle.addPlayer(CIVILIAN, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } } })
handle.players[OFFICER].data.items = { { name = 'handcuffs', amount = 1 } }

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

h.test('cuffing an already-cuffed target re-applies the restraint instead of failing', function()
    local before = #handle.clientEventsFor('qbpolice:client:cuffed')
    local ok, err, info = Police.cuff(OFFICER, SUSPECT)
    h.assertTrue(ok, tostring(err))
    h.assertEqual(info, 'refreshed')
    h.assertTrue(Police.isCuffed(SUSPECT))
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:cuffed'), before + 1)
end)

h.test('Config.cuff.recuffRefreshes = false keeps the old "already cuffed" refusal', function()
    Config.cuff.recuffRefreshes = false
    local ok, err = Police.cuff(OFFICER, SUSPECT)
    Config.cuff.recuffRefreshes = nil
    h.assertFalse(ok)
    h.assertEqual(err, 'already cuffed')
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
    h.assertEqual(handle.lastNotification().src, CIVILIAN)
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

h.test('soft cuffs require the actual item through direct, usable and legacy calls', function()
    Police.uncuff(OFFICER, CIVILIAN)
    handle.setCoords(OFFICER, FAR, FAR, 0)
    handle.setCoords(SUSPECT, 0, 0, 0)
    handle.setCoords(CIVILIAN, 0, 0, 0)
    handle.players[CIVILIAN].data.items = {}
    local before = #handle.clientEventsFor('qbpolice:client:cuffed')

    local ok, err = Police.softCuffNearby(CIVILIAN)
    h.assertFalse(ok)
    h.assertEqual(err, 'handcuffs required')
    h.assertFalse(useables.handcuffs(CIVILIAN))
    handle.fireEvent('police:server:CuffPlayerSoft', CIVILIAN, 'handcuffs', true)
    h.assertFalse(Police.isCuffed(SUSPECT))
    h.assertEqual(Police.cuffState[SUSPECT], nil)
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:cuffed'), before)
    h.assertEqual(handle.lastClient('QBCore:Notify').args[1], 'handcuffs required')
end)

h.test('a civilian carrying handcuffs can still use them without consuming the item', function()
    Police.uncuff(SUSPECT, SUSPECT)
    local items = { { name = 'handcuffs', amount = 1 } }
    handle.players[CIVILIAN].data.items = items
    h.assertTrue(useables.handcuffs(CIVILIAN))
    h.assertTrue(Police.isCuffed(SUSPECT))
    h.assertTrue(Police.cuffState[SUSPECT].soft)
    h.assertEqual(items[1].amount, 1)
    Police.uncuff(SUSPECT, SUSPECT)
end)

h.test('soft-cuff target selection ignores other routing instances', function()
    GetPlayerRoutingBucket = function(src) return src == SUSPECT and 9 or 0 end
    local before = #handle.clientEventsFor('qbpolice:client:cuffed')
    local ok, err = Police.softCuffNearby(CIVILIAN)
    handle.fireEvent('police:server:CuffPlayerSoft', CIVILIAN)
    GetPlayerRoutingBucket = function() return 0 end

    h.assertFalse(ok)
    h.assertEqual(err, 'no one nearby to cuff')
    h.assertFalse(Police.isCuffed(SUSPECT))
    h.assertEqual(Police.cuffState[SUSPECT], nil)
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:cuffed'), before)
end)

h.test('one same-instance target is selected when an invisible target is also nearby', function()
    Police.uncuff(SUSPECT, SUSPECT)
    handle.setCoords(OFFICER, 0, 0, 0)
    GetPlayerRoutingBucket = function(src) return src == SUSPECT and 9 or 0 end
    local ok, err = Police.softCuffNearby(CIVILIAN)
    GetPlayerRoutingBucket = function() return 0 end
    h.assertTrue(ok, tostring(err))
    h.assertTrue(Police.isCuffed(OFFICER))
    h.assertFalse(Police.isCuffed(SUSPECT))
    Police.uncuff(OFFICER, OFFICER)
end)

-- ---------------------------------------------------------------------------
-- Single source of truth: the replicated state bag, re-cuff, uncuff and login.
-- ---------------------------------------------------------------------------
local function resetAll()
    for _, who in ipairs({ OFFICER, SUSPECT, CIVILIAN }) do
        handle.players[who].data.metadata.ishandcuffed = false
        Police.cuffState[who] = nil
        handle.stateBag(who):set('koraCuffed', false, true)
        handle.stateBag(who):set('koraCuffedSoft', false, true)
    end
    handle.players[OFFICER].job.onduty = true
    handle.players[OFFICER].data.items = { { name = 'handcuffs', amount = 1 } }
    handle.players[SUSPECT].data.items = {}
    handle.setCoords(OFFICER, 0.0, 0.0, 0.0)
    handle.setCoords(SUSPECT, 0.0, 0.0, 0.0)
    handle.setCoords(CIVILIAN, 0.0, FAR, 0.0)
    Config.cuff.recuffRefreshes, Config.cuff.cufferCanUncuff, Config.cuff.restoreOnLogin = nil, nil, nil
end

h.test('cuffing and uncuffing write the replicated bag, soft flag included', function()
    resetAll()
    h.assertTrue(Police.cuff(OFFICER, SUSPECT))
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, true)
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffedSoft, false)
    h.assertTrue(Police.uncuff(OFFICER, SUSPECT))
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, false)

    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0); handle.setCoords(SUSPECT, 0.0, FAR, 0.0)
    h.assertTrue(Police.softCuffNearby(OFFICER))
    h.assertEqual(handle.stateBag(CIVILIAN).koraCuffed, true)
    h.assertEqual(handle.stateBag(CIVILIAN).koraCuffedSoft, true)
end)

h.test('the handcuffs item on a player who is already cuffed re-applies the cuff, not "no one nearby"', function()
    resetAll()
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0); handle.setCoords(SUSPECT, 0.0, FAR, 0.0)
    h.assertTrue(Police.softCuffNearby(OFFICER))
    local before = #handle.clientEventsFor('qbpolice:client:cuffed')
    local ok, err, info = Police.softCuffNearby(OFFICER)
    h.assertTrue(ok, tostring(err))
    h.assertEqual(info, 'refreshed')
    h.assertTrue(Police.isCuffed(CIVILIAN))
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:cuffed'), before + 1)

    Config.cuff.recuffRefreshes = false
    local refused, refusal = Police.softCuffNearby(OFFICER)
    h.assertFalse(refused)
    h.assertEqual(refusal, 'already cuffed')
end)

h.test('the item picks the player who is not cuffed when a cuffed one is also in reach', function()
    resetAll()
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0); handle.setCoords(SUSPECT, 0.0, FAR, 0.0)
    h.assertTrue(Police.softCuffNearby(OFFICER))
    handle.setCoords(SUSPECT, 0.0, 0.0, 0.0)
    h.assertTrue(Police.softCuffNearby(OFFICER))
    h.assertTrue(Police.isCuffed(SUSPECT))
    local ok, err = Police.softCuffNearby(OFFICER)
    h.assertFalse(ok)
    h.assertTrue(err:find('too many', 1, true) ~= nil)
end)

h.test('an officer cuff hardens a soft cuff and a soft cuff never softens a hard one', function()
    resetAll()
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0); handle.setCoords(SUSPECT, 0.0, FAR, 0.0)
    h.assertTrue(Police.softCuffNearby(OFFICER))
    h.assertTrue(Police.cuffState[CIVILIAN].soft)
    h.assertTrue(Police.cuff(OFFICER, CIVILIAN))
    h.assertFalse(Police.cuffState[CIVILIAN].soft)
    h.assertEqual(handle.stateBag(CIVILIAN).koraCuffedSoft, false)
    h.assertTrue(Police.softCuffNearby(OFFICER))
    h.assertFalse(Police.cuffState[CIVILIAN].soft)
end)

h.test('uncuff clears a cuffed target and a stale client of a target that is not cuffed', function()
    resetAll()
    h.assertTrue(Police.cuff(OFFICER, SUSPECT))
    h.assertTrue(Police.uncuff(OFFICER, SUSPECT))
    local before = #handle.clientEventsFor('qbpolice:client:cuffed')
    local ok, err = Police.uncuff(OFFICER, SUSPECT)
    h.assertFalse(ok)
    h.assertEqual(err, 'not cuffed')
    local events = handle.clientEventsFor('qbpolice:client:cuffed')
    h.assertEqual(#events, before + 1)
    h.assertEqual(events[#events].args[1], false)
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, false)
end)

h.test('a client cannot flip its own cuffed bag', function()
    resetAll()
    handle.stateBag(SUSPECT):set('koraCuffed', true, true)
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, false)
    h.assertTrue(Police.cuff(OFFICER, SUSPECT))
    handle.stateBag(SUSPECT):set('koraCuffed', false, true)
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, true)
    h.assertTrue(Police.isCuffed(SUSPECT))
end)

h.test('whoever soft-cuffed a player can uncuff them; a stranger and a hard cuff are refused', function()
    resetAll()
    handle.players[OFFICER].job.onduty = false
    handle.players[SUSPECT].data.items = { { name = 'handcuffs', amount = 1 } }
    handle.players[OFFICER].data.items = {}
    handle.setCoords(SUSPECT, 0.0, 0.0, 0.0); handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0)
    handle.setCoords(OFFICER, FAR, FAR, 0.0)
    h.assertTrue(Police.softCuffNearby(SUSPECT))
    h.assertTrue(Police.isCuffed(CIVILIAN))
    handle.setCoords(OFFICER, 0.0, 0.0, 0.0)
    local ok, err = Police.uncuff(OFFICER, CIVILIAN)
    h.assertFalse(ok); h.assertEqual(err, 'not authorised')
    Config.cuff.cufferCanUncuff = false
    ok, err = Police.uncuff(SUSPECT, CIVILIAN)
    h.assertFalse(ok); h.assertEqual(err, 'not authorised')
    Config.cuff.cufferCanUncuff = nil
    h.assertTrue(Police.uncuff(SUSPECT, CIVILIAN))
    h.assertFalse(Police.isCuffed(CIVILIAN))

    handle.players[OFFICER].job.onduty = true
    h.assertTrue(Police.cuff(OFFICER, CIVILIAN))
    ok, err = Police.uncuff(SUSPECT, CIVILIAN)
    h.assertFalse(ok); h.assertEqual(err, 'not authorised')
end)

h.test('joining with no cuff is not cuffed and sends no cuff event', function()
    resetAll()
    local before = #handle.clientEventsFor('qbpolice:client:cuffed')
    handle.fireEvent('qbcore:server:playerLoaded', 0, SUSPECT, 'CID2')
    h.assertFalse(Police.isCuffed(SUSPECT))
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, false)
    h.assertEqual(Police.cuffState[SUSPECT], nil)
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:cuffed'), before)
end)

h.test('a stored cuff with no live session is cleared at login by default', function()
    resetAll()
    handle.players[SUSPECT].data.metadata.ishandcuffed = true
    handle.fireEvent('qbcore:server:playerLoaded', 0, SUSPECT, 'CID2')
    h.assertFalse(Police.isCuffed(SUSPECT))
    h.assertEqual(handle.players[SUSPECT].data.metadata.ishandcuffed, false)
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, false)
    h.assertEqual(Police.cuffState[SUSPECT], nil)
    local events = handle.clientEventsFor('qbpolice:client:cuffed')
    h.assertEqual(events[#events].target, SUSPECT)
    h.assertEqual(events[#events].args[1], false)
end)

h.test('Config.cuff.restoreOnLogin = true brings a stored cuff back as a hard cuff', function()
    resetAll()
    Config.cuff.restoreOnLogin = true
    handle.players[SUSPECT].data.metadata.ishandcuffed = true
    local before = #handle.clientEventsFor('qbpolice:client:cuffed')
    handle.fireEvent('qbcore:server:playerLoaded', 0, SUSPECT, 'CID2')
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, true)
    h.assertTrue(Police.cuffState[SUSPECT] ~= nil)
    h.assertFalse(Police.cuffState[SUSPECT].soft)
    local events = handle.clientEventsFor('qbpolice:client:cuffed')
    h.assertEqual(#events, before + 1)
    h.assertEqual(events[#events].args[1], true)
end)

h.test('drop and rejoin comes back uncuffed', function()
    resetAll()
    h.assertTrue(Police.cuff(OFFICER, SUSPECT))
    handle.fireEvent('QBCore:Server:OnPlayerUnload', 0, SUSPECT)
    handle.fireEvent('playerDropped', SUSPECT)
    h.assertEqual(Police.cuffState[SUSPECT], nil)
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, false)
    handle.fireEvent('qbcore:server:playerLoaded', 0, SUSPECT, 'CID2')
    h.assertFalse(Police.isCuffed(SUSPECT))
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, false)
end)

h.test('a logout clears the bag and tells the client; the next character loads uncuffed', function()
    resetAll()
    h.assertTrue(Police.cuff(OFFICER, SUSPECT))
    local before = #handle.clientEventsFor('qbpolice:client:cuffed')
    handle.fireEvent('QBCore:Server:OnPlayerUnload', 0, SUSPECT)
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, false)
    local events = handle.clientEventsFor('qbpolice:client:cuffed')
    h.assertEqual(#events, before + 1)
    h.assertEqual(events[#events].args[1], false)
    handle.fireEvent('qbcore:server:playerLoaded', 0, SUSPECT, 'CID9')
    h.assertFalse(Police.isCuffed(SUSPECT))
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, false)
end)

h.test('a restart of this resource keeps a session cuff and clears a stale one', function()
    resetAll()
    h.assertTrue(Police.softCuffNearby(OFFICER))
    h.assertTrue(Police.cuffState[SUSPECT].soft)
    Police.cuffState[SUSPECT] = nil -- what a restart loses
    handle.fireEvent('onResourceStart', 0, 'kora_police')
    h.assertTrue(Police.isCuffed(SUSPECT))
    h.assertTrue(Police.cuffState[SUSPECT].soft)
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, true)

    resetAll()
    handle.players[SUSPECT].data.metadata.ishandcuffed = true
    handle.fireEvent('onResourceStart', 0, 'kora_police')
    h.assertFalse(Police.isCuffed(SUSPECT))
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, false)
end)

h.test('the resync callback answers with the session state and repairs the rest', function()
    local resync = Kora.callback.registry['kora_police:server:resyncCuff']
    resetAll()
    local cuffed, soft = resync(SUSPECT)
    h.assertFalse(cuffed); h.assertFalse(soft)

    handle.players[SUSPECT].data.metadata.ishandcuffed = true -- stored, but no session
    cuffed = resync(SUSPECT)
    h.assertFalse(cuffed)
    h.assertFalse(Police.isCuffed(SUSPECT))

    h.assertTrue(Police.cuff(OFFICER, SUSPECT))
    cuffed, soft = resync(SUSPECT)
    h.assertTrue(cuffed); h.assertFalse(soft)
    h.assertEqual(handle.stateBag(SUSPECT).koraCuffed, true)
end)

h.test('a restrained player cannot cuff anyone, and a drop clears their cuff state', function()
    resetAll()
    handle.players[OFFICER].data.metadata.ishandcuffed = true
    local ok, err = Police.cuff(OFFICER, SUSPECT)
    h.assertFalse(ok); h.assertEqual(err, 'you are restrained')
    handle.players[OFFICER].data.metadata.ishandcuffed = false
    h.assertTrue(Police.cuff(OFFICER, SUSPECT))
    handle.fireEvent('playerDropped', SUSPECT)
    h.assertEqual(Police.cuffState[SUSPECT], nil)
    h.assertTrue(Police.isCuffed(SUSPECT), 'the persisted cuff outlives the session')
end)

h.test('every cuffed-only target option reads the replicated bag, not the local ped', function()
    for _, file in ipairs({ 'cuff', 'search', 'seize', 'jail', 'escort', 'fingerprint', 'tracker', 'rob' }) do
        local f = assert(io.open('client/' .. file .. '.lua', 'r')); local src = f:read('*a'); f:close()
        h.assertFalse(src:find('IsPedCuffed', 1, true), file .. ' still trusts IsPedCuffed')
    end
end)

h.test('uncuffing an escorted suspect ends the escort on both sides', function()
    resetAll()
    h.assertTrue(Police.cuff(OFFICER, SUSPECT))
    h.assertTrue(Police.escort(OFFICER, SUSPECT))
    local stops, selfStops = #handle.clientEventsFor('qbpolice:client:escortStop'), #handle.clientEventsFor('qbpolice:client:escortStopSelf')
    h.assertTrue(Police.uncuff(OFFICER, SUSPECT))
    h.assertEqual(Police.escorted[SUSPECT], nil)
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:escortStop'), stops + 1, 'the suspect detaches')
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:escortStopSelf'), selfStops + 1, 'the officer is told')
    local events = handle.clientEventsFor('qbpolice:client:cuffed')
    h.assertEqual(events[#events].args[1], false)
end)

h.report('cuff')
