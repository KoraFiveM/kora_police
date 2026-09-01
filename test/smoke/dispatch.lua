-- Police calls: what qbpolice puts INTO a dispatch call, and the cop-count
-- broadcast. The call lifecycle itself (storage, expiry, recipients) belongs to
-- qbdispatch and has its own suite -- this only asserts the payload qbpolice
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

h.test('backup names the requesting officer by callsign', function()
    _G.source = COP1
    TriggerEvent('qbpolice:server:requestBackup', {})

    local call = handle.lastDispatchCall()
    h.assertEqual(call.code, '10-78', 'a backup request has its own code')
    h.assertEqual(call.priority, 2, 'backup is high priority, not critical')
    h.assertTrue(call.message:find('1-ADAM-12', 1, true) ~= nil,
        'dispatch reads out the callsign, not a source id: ' .. tostring(call.message))
end)

h.test('a civilian cannot request police backup', function()
    handle.addPlayer(9, { job = { name = 'unemployed', onduty = true, grade = { level = 1 } } })
    local before = #handle.dispatchCalls

    _G.source = 9
    TriggerEvent('qbpolice:server:requestBackup', { message = 'send everyone' })

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
    handle.setCoords(COP1, 111.0, 222.0, 33.0)
    _G.source = COP1
    TriggerEvent('qbpolice:server:panic')

    local call = handle.dispatchCalls[#handle.dispatchCalls - 1]
    h.assertEqual(call.coords.x, 111.0, "read from the officer's own ped")
    h.assertEqual(call.coords.y, 222.0, 'so a modified client cannot pull every unit to a chosen spot')
end)

h.test('a client-reported crime is re-anchored to the reporter position', function()
    handle.setCoords(9, 500.0, 600.0, 20.0)
    _G.source = 9

    TriggerEvent('qbpolice:server:crimeDetected', {
        code = '10-31', title = 'Shots Fired', priority = 1,
        coords = { x = -9999.0, y = -9999.0, z = 0.0 }, -- a lying client
    })

    local call = handle.lastDispatchCall()
    h.assertEqual(call.coords.x, 500.0, 'the payload coordinates are ignored entirely')
    h.assertEqual(call.title, 'Shots Fired', 'the descriptive fields still come from the detector')
end)

h.test('a malformed crime report is dropped rather than raising a blank call', function()
    local before = #handle.dispatchCalls
    _G.source = 9
    TriggerEvent('qbpolice:server:crimeDetected', 'not a table')
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
