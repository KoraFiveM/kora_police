-- Police.seizeCash/seizeDriverLicense -- officer authority, restraint
-- requirement, and the actual cash transfer accounting.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/cuff.lua')
dofile('server/seize.lua')

local OFFICER, SUSPECT = 1, 2

handle.addPlayer(OFFICER, { job = { name = 'police', onduty = true, grade = { level = 1 } }, money = { cash = 0, bank = 0 } })
handle.addPlayer(SUSPECT, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } }, money = { cash = 250, bank = 1000 } })

h.test('cannot seize cash from an unrestrained suspect', function()
    local ok, err = Police.seizeCash(OFFICER, SUSPECT)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('an off-duty player cannot seize cash even from a cuffed suspect', function()
    Police.cuff(OFFICER, SUSPECT)
    handle.players[OFFICER].job.onduty = false
    local ok, err = Police.seizeCash(OFFICER, SUSPECT)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    handle.players[OFFICER].job.onduty = true
end)

h.test('seizing cash moves the suspect\'s full cash balance to the officer', function()
    local ok, err, amount = Police.seizeCash(OFFICER, SUSPECT)
    h.assertTrue(ok, tostring(err))
    h.assertEqual(amount, 250)
    h.assertEqual(handle.players[SUSPECT].data.money.cash, 0)
    h.assertEqual(handle.players[OFFICER].data.money.cash, 250)
end)

h.test('seizing cash from a suspect carrying none fails', function()
    local ok, err = Police.seizeCash(OFFICER, SUSPECT)
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('seizing a driver license flags the metadata and does not touch other licences', function()
    handle.players[SUSPECT].data.metadata.licences = { weapon = true }
    local ok = Police.seizeDriverLicense(OFFICER, SUSPECT)
    h.assertTrue(ok)
    h.assertEqual(handle.players[SUSPECT].data.metadata.licences.driver, false)
    h.assertEqual(handle.players[SUSPECT].data.metadata.licences.weapon, true)
end)

h.report('seize')
