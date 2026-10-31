local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

dofile('config.lua')
dofile('server/core.lua')
dofile('server/duty.lua')

local officer = 41
handle.addPlayer(officer, {
    job = { name = Config.police.job, onduty = false, grade = { level = 1 } },
})

h.test('police duty event rejects a remote officer', function()
    local toggle = handle.Kora.events.registry['qbpolice:server:toggleDuty']
    h.assertTrue(type(toggle) == 'function')
    toggle(officer)
    h.assertFalse(handle.players[officer].job.onduty)
end)

h.test('police duty event accepts an officer at a configured duty point', function()
    local point = Config.duty.points[1].coords
    handle.setCoords(officer, point.x, point.y, point.z)
    handle.Kora.events.registry['qbpolice:server:toggleDuty'](officer)
    h.assertTrue(handle.players[officer].job.onduty)
end)

h.test('police duty command uses the same location policy', function()
    handle.advanceClock(Config.duty.actionCooldown)
    handle.setCoords(officer, 0, 0, 0)
    handle.Kora.commands.registry['police-duty'](officer)
    h.assertTrue(handle.players[officer].job.onduty, 'remote command must not toggle duty')

    local point = Config.duty.points[1].coords
    handle.setCoords(officer, point.x, point.y, point.z)
    handle.Kora.commands.registry['police-duty'](officer)
    h.assertFalse(handle.players[officer].job.onduty)
end)

h.report('duty access')
