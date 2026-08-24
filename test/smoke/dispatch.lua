-- Police.dispatch (defaults jobs={'police'}, forwards to exports.qbcore:alert)
-- and the duty-change cop-count broadcast. Core.dispatch.alert's own
-- fan-out/legacy-event logic lives in qbcore and is not re-tested here.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/dispatch.lua')

local COP1, COP2, EMS1 = 1, 2, 3

handle.addPlayer(COP1, { job = { name = 'police', onduty = true, grade = { level = 1 } } })
handle.addPlayer(COP2, { job = { name = 'police', onduty = false, grade = { level = 1 } } })
handle.addPlayer(EMS1, { job = { name = 'ambulance', onduty = true, grade = { level = 1 } } })

local function eventsFor(name) return handle.clientEventsFor(name) end

h.test('Police.dispatch defaults jobs to the configured police job', function()
    local count = Police.dispatch({ title = 'Robbery', message = '10-90 in progress' })
    h.assertEqual(count, 1, 'only the one on-duty cop should be notified')
    local hits = eventsFor('qbcore:client:dispatchAlert')
    h.assertTrue(#hits >= 1)
    h.assertEqual(hits[#hits].target, COP1)
    h.assertEqual(hits[#hits].args[1].jobs[1], Config.police.job)
end)

h.test('Police.dispatch defaults radius from Config.dispatch.robberyRadius', function()
    Police.dispatch({ title = 'Test' })
    local hits = eventsFor('qbcore:client:dispatchAlert')
    h.assertEqual(hits[#hits].args[1].radius, Config.dispatch.robberyRadius)
end)

h.test('an explicit jobs list is preserved rather than overwritten', function()
    local count = Police.dispatch({ jobs = { 'police', 'ambulance' }, title = 'Multi' })
    h.assertEqual(count, 2)
end)

h.test('broadcastCopCount only reaches on-duty officers', function()
    Police.broadcastCopCount()
    local hits = eventsFor('qbpolice:client:updateCopCount')
    local targets = {}
    for _, e in ipairs(hits) do targets[e.target] = e.args[1] end
    h.assertEqual(targets[COP1], 1, 'COP1 (on duty) should have received the count')
    h.assertEqual(targets[COP2], nil, 'COP2 (off duty) should not have received a push')
end)

h.test('going on duty triggers a fresh cop-count broadcast to on-duty officers', function()
    handle.players[COP2].job.onduty = true
    local before = #eventsFor('qbpolice:client:updateCopCount')
    TriggerEvent('QBCore:Server:SetDuty', COP2, true)
    local hits = eventsFor('qbpolice:client:updateCopCount')
    h.assertTrue(#hits > before)
    h.assertEqual(hits[#hits].args[1], 2, 'both officers should now be counted')
end)

h.report('dispatch')
