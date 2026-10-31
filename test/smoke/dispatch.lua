-- Police calls: what kora_police puts INTO a dispatch call, and the cop-count
-- broadcast. The call lifecycle itself (storage, expiry, recipients) belongs to
-- kora_dispatch and has its own suite -- this only asserts the payload kora_police
-- builds and who it is addressed to.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/dispatch.lua')

local COP1, COP2, EMS1, DEPUTY = 1, 2, 3, 4

handle.addPlayer(COP1, { job = { name = 'police', onduty = true, grade = { level = 1 } },
                         name = 'Jane Doe', callsign = '1-ADAM-12' })
handle.addPlayer(COP2, { job = { name = 'police', onduty = false, grade = { level = 1 } } })
handle.addPlayer(EMS1, { job = { name = 'ambulance', onduty = true, grade = { level = 1 } } })
handle.addPlayer(DEPUTY, { job = { name = 'sheriff', onduty = true, grade = { level = 1 } },
                           name = 'Sam Reed', callsign = 'S-01' })

local function eventsFor(name) return handle.clientEventsFor(name) end

h.test('a police call targets the LEO job TYPE, not just this resource job name', function()
    local _, count = Police.dispatch({ title = 'Robbery', message = '10-90 in progress' })
    local call = handle.lastDispatchCall()

    h.assertEqual(call.jobTypes[1], 'leo', 'the whole law-enforcement service is targeted')
    h.assertEqual(call.jobs, nil, 'not a hard-coded job name')
    -- A server adding a sheriff department gets them on the radio with no code
    -- change here; that is the entire point of dispatching by type.
    h.assertEqual(count, 2, 'the on-duty officer and the on-duty deputy, not the off-duty cop')
end)

h.test('an explicit target is preserved rather than overwritten', function()
    Police.dispatch({ jobs = { 'police' }, title = 'Police only' })
    h.assertEqual(handle.lastDispatchCall().jobs[1], 'police', 'an explicit job list wins')
    h.assertEqual(handle.lastDispatchCall().jobTypes, nil, 'and no default type is added on top')
end)

h.test('the configured robbery radius rides along on the call', function()
    Police.dispatch({ title = 'Test' })
    h.assertEqual(handle.lastDispatchCall().radius, Config.dispatch.robberyRadius, 'radius defaulted')
end)

h.test('backup uses its registered fixed presentation', function()
    handle.Kora.events.registry['qbpolice:server:requestBackup'](COP1)

    local call = handle.lastDispatchCall()
    h.assertEqual(call.code, '10-78', 'a backup request has its own code')
    h.assertEqual(call.priority, 2, 'backup is high priority, not critical')
    h.assertEqual(call.message, 'An on-duty officer is requesting backup.',
        'a caller cannot inject arbitrary dispatch presentation')
end)

h.test('a civilian cannot request police backup', function()
    handle.addPlayer(9, { job = { name = 'unemployed', onduty = true, grade = { level = 1 } } })
    local before = #handle.dispatchCalls

    handle.Kora.events.registry['qbpolice:server:requestBackup'](9)

    h.assertEqual(#handle.dispatchCalls, before, 'no call should have been raised')
end)

h.test('the panic button raises TWO calls, one per service', function()
    local before = #handle.dispatchCalls
    _G.source = COP1
    TriggerEvent('qbpolice:server:panic')

    h.assertEqual(#handle.dispatchCalls, before + 2, 'police and EMS are separate incidents')

    local leo = handle.dispatchCalls[before + 1]
    local ems = handle.dispatchCalls[before + 2]

    h.assertEqual(leo.jobTypes[1], 'leo', 'the first goes to law enforcement')
    h.assertEqual(leo.code, '10-99', 'officer down')
    h.assertEqual(ems.jobTypes[1], 'ems', 'the second goes to EMS')
    h.assertEqual(ems.code, '10-52', 'as a medical call')

    -- Both are priority 1 but they are worded for their own service: one asks
    -- for backup, the other for a patient.
    h.assertTrue(leo.message:find('panic alarm', 1, true) ~= nil, 'the police wording')
    h.assertTrue(ems.message:find('medical', 1, true) ~= nil, 'the EMS wording')
end)

h.test('panic coordinates come from the server, never the client', function()
    Police.clearPanicCooldown(COP1) -- the previous test just used the alarm
    handle.setCoords(COP1, 111.0, 222.0, 33.0)
    _G.source = COP1
    TriggerEvent('qbpolice:server:panic')

    local call = handle.dispatchCalls[#handle.dispatchCalls - 1]
    h.assertEqual(call.coords.x, 111.0, "read from the officer's own ped")
    h.assertEqual(call.coords.y, 222.0, 'so a modified client cannot pull every unit to a chosen spot')
end)

-- --- panic cooldown ---------------------------------------------------------

h.test('a mashed panic button raises one alarm, not one per press', function()
    Police.clearPanicCooldown(COP1)
    local before = #handle.dispatchCalls

    _G.source = COP1
    for _ = 1, 5 do TriggerEvent('qbpolice:server:panic') end

    -- One press is already TWO calls (LEO + EMS). Without the gate, five
    -- presses would put ten duplicates across both services' feeds, at exactly
    -- the moment a clean feed matters most.
    h.assertEqual(#handle.dispatchCalls, before + 2, 'only the first press raised anything')
end)

h.test('a suppressed press tells the officer their alarm is already out', function()
    Police.clearPanicCooldown(COP1)
    _G.source = COP1
    TriggerEvent('qbpolice:server:panic')

    TriggerEvent('qbpolice:server:panic')

    -- Silence would be the wrong answer here: somebody pressing this is having
    -- the worst moment of their shift and needs to know it was heard.
    local note = handle.lastNotification()
    h.assertEqual(note.src, COP1, 'addressed to the officer')
    h.assertTrue(note.payload.message:find('already active', 1, true) ~= nil,
        'and says the alarm is out: ' .. tostring(note.payload.message))
end)

h.test('the alarm can be raised again once the cooldown elapses', function()
    Police.clearPanicCooldown(COP1)
    _G.source = COP1
    TriggerEvent('qbpolice:server:panic')
    local before = #handle.dispatchCalls

    handle.advanceClock(Config.dispatch.panicCooldown + 1)
    TriggerEvent('qbpolice:server:panic')

    -- An officer still down a minute later, in a new position, is raising a
    -- genuinely new alarm.
    h.assertEqual(#handle.dispatchCalls, before + 2, 'a fresh alarm after the window')
end)

h.test('the cooldown is per officer, not global', function()
    Police.clearPanicCooldown(COP1)
    Police.clearPanicCooldown(DEPUTY)

    _G.source = COP1
    TriggerEvent('qbpolice:server:panic')
    local before = #handle.dispatchCalls

    -- A sheriff's deputy, deliberately: dispatch targets the LEO service, so a
    -- deputy receives these calls and must be able to raise one too.
    _G.source = DEPUTY
    TriggerEvent('qbpolice:server:panic')

    h.assertEqual(#handle.dispatchCalls, before + 2,
        "one officer's alarm must never mute another officer's")
end)

h.test('a sheriff can raise LEO calls, a civilian cannot', function()
    -- Police.isPolice gates on the job NAME, which is right for this force's
    -- armory and evidence but wrong for dispatch -- being alerted to an officer
    -- down while unable to raise your own alarm is the worst of both.
    h.assertTrue(Police.isLeo(DEPUTY), 'an on-duty deputy is law enforcement')
    h.assertTrue(Police.isLeo(COP1), 'so is an on-duty officer')
    h.assertFalse(Police.isLeo(EMS1), 'a paramedic is not')
    h.assertFalse(Police.isLeo(9), 'nor is a civilian')

    -- COP2 is off duty in the fixture and must be left that way -- the
    -- cop-count assertions further down depend on it.
    h.assertFalse(Police.isLeo(COP2), 'nor is an off-duty officer')
end)

h.test('going off duty clears the cooldown', function()
    Police.clearPanicCooldown(COP1)
    _G.source = COP1
    TriggerEvent('qbpolice:server:panic')

    -- Off duty ends the shift the alarm belonged to; coming back on and
    -- immediately needing help is a new emergency, not a repeat of the old one.
    TriggerEvent('QBCore:Server:SetDuty', COP1, false)

    local elapsed = Police.panicCooldownElapsed(COP1)
    h.assertTrue(elapsed, 'the cooldown should not survive the shift')
end)

h.test('a client-reported crime selects only a registered fixed incident', function()
    handle.setCoords(9, 500.0, 600.0, 20.0)
    handle.Kora.events.registry['qbpolice:server:crimeDetected'](9, 'qbpolice:gunfire')

    local call = handle.lastDispatchCall()
    h.assertEqual(call.coords.x, 500.0, 'coordinates are derived from the reporter')
    h.assertEqual(call.title, 'Shots Fired', 'presentation comes from the server registration')
end)

h.test('an unknown crime key is dropped rather than raising a call', function()
    local before = #handle.dispatchCalls
    handle.Kora.events.registry['qbpolice:server:crimeDetected'](9, 'qbpolice:not-registered')
    h.assertEqual(#handle.dispatchCalls, before, 'nothing raised')
end)

-- --- cop count --------------------------------------------------------------

h.test('broadcastCopCount counts the whole LEO service and reaches only on-duty units', function()
    Police.broadcastCopCount()

    local targets = {}
    for _, e in ipairs(eventsFor('qbpolice:client:updateCopCount')) do targets[e.target] = e.args[1] end

    h.assertEqual(targets[COP1], 2, 'the officer sees both LEO units on duty')
    h.assertEqual(targets[DEPUTY], 2, 'and so does the deputy -- one shared count for the service')
    h.assertEqual(targets[COP2], nil, 'the off-duty officer receives no push')
    h.assertEqual(targets[EMS1], nil, 'nor does EMS')
end)

h.test('going on duty triggers a fresh broadcast', function()
    handle.players[COP2].job.onduty = true
    local before = #eventsFor('qbpolice:client:updateCopCount')

    TriggerEvent('QBCore:Server:SetDuty', COP2, true)

    local hits = eventsFor('qbpolice:client:updateCopCount')
    h.assertTrue(#hits > before, 'a duty change re-broadcasts')
    h.assertEqual(hits[#hits].args[1], 3, 'all three LEO units are now counted')
end)

h.report('dispatch')
