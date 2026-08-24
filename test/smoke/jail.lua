-- Police.jailPlayer -- thin wrapper over exports.qbcore:jailPlayer: officer
-- authority check, default minutes, and clearing cuff/escort/drag state on
-- booking. The jail mechanism itself (teleport/timer/persistence/external-
-- prison deference) is qbcore's own Core.jail and is not re-tested here.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/cuff.lua')
dofile('server/escort.lua')
dofile('server/jail.lua')

local OFFICER, SUSPECT, CIVILIAN = 1, 2, 3

handle.addPlayer(OFFICER, { job = { name = 'police', onduty = true, grade = { level = 1 } } })
handle.addPlayer(SUSPECT, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } } })
handle.addPlayer(CIVILIAN, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } } })

h.test('an off-duty player cannot jail anyone', function()
    handle.players[OFFICER].job.onduty = false
    local ok, err = Police.jailPlayer(OFFICER, SUSPECT, 10)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    handle.players[OFFICER].job.onduty = true
end)

h.test('jailing an unknown target fails', function()
    local ok, err = Police.jailPlayer(OFFICER, 999, 10)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('an on-duty officer jails a target for the given minutes', function()
    local ok = Police.jailPlayer(OFFICER, SUSPECT, 15, 'grand theft auto')
    h.assertTrue(ok)
    h.assertEqual(handle.players[SUSPECT].jailed.minutes, 15)
    h.assertEqual(handle.players[SUSPECT].jailed.reason, 'grand theft auto')
end)

h.test('omitting minutes falls back to Config.jail.defaultMinutes', function()
    local ok = Police.jailPlayer(OFFICER, CIVILIAN)
    h.assertTrue(ok)
    h.assertEqual(handle.players[CIVILIAN].jailed.minutes, Config.jail.defaultMinutes)
end)

h.test('booking clears cuff/escort state', function()
    handle.setCoords(OFFICER, 0.0, 0.0, 0.0)
    handle.setCoords(SUSPECT, 0.0, 0.0, 0.0)
    Police.cuff(OFFICER, SUSPECT)
    Police.escort(OFFICER, SUSPECT)
    h.assertTrue(Police.isCuffed(SUSPECT))
    h.assertEqual(Police.getEscorted(SUSPECT), OFFICER)

    Police.jailPlayer(OFFICER, SUSPECT, 5)

    h.assertFalse(Police.isCuffed(SUSPECT))
    h.assertEqual(Police.getEscorted(SUSPECT), nil)
end)

h.test('a non-positive sentence is rejected by the underlying jail (surfaced through the wrapper)', function()
    local ok, err = Police.jailPlayer(OFFICER, SUSPECT, 0)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.report('jail')
