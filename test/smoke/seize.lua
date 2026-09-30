-- Police.seizeCash/seizeDriverLicense -- officer authority, restraint
-- requirement, and the actual cash transfer accounting.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/cuff.lua')
dofile(arg[1] or 'server/seize.lua')
dofile('server/compat/police.lua')

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

for _, case in ipairs({ 'distant', 'different instance' }) do
    h.test('cash seizure rejects a ' .. case .. ' target through every entry point', function()
        handle.players[SUSPECT].data.money.cash = 1000
        handle.players[OFFICER].data.money.cash = 0
        handle.setCoords(SUSPECT, case == 'distant' and 10000 or 0, 0, 0)
        GetPlayerRoutingBucket = function(src) return case == 'different instance' and src == SUSPECT and 9 or 0 end

        local money = handle.exportImpls.qbcore
        local read, transfer = money.getMoney, money.transferMoney
        local reads, transfers = 0, 0
        money.getMoney = function(...) reads = reads + 1; return read(...) end
        money.transferMoney = function(...) transfers = transfers + 1; return transfer(...) end
        local ok, err = Police.seizeCash(OFFICER, SUSPECT)
        local reasons = {}
        for _, name in ipairs({ 'qbpolice:server:seizeCash', 'police:server:SeizeCash' }) do
            handle.fireEvent(name, OFFICER, tostring(SUSPECT))
            reasons[#reasons + 1] = handle.lastClient('QBCore:Notify').args[1]
        end
        money.getMoney, money.transferMoney = read, transfer
        GetPlayerRoutingBucket = function() return 0 end
        handle.setCoords(SUSPECT, 0, 0, 0)

        h.assertFalse(ok)
        h.assertEqual(err, 'too far away')
        for _, reason in ipairs(reasons) do h.assertEqual(reason, 'too far away') end
        h.assertEqual(reads, 0)
        h.assertEqual(transfers, 0)
        h.assertEqual(handle.players[SUSPECT].data.money.cash, 1000)
        h.assertEqual(handle.players[OFFICER].data.money.cash, 0)
    end)
end

h.test('cash seizure at the configured distance still preserves its return contract', function()
    handle.players[SUSPECT].data.money.cash = 1000
    handle.players[OFFICER].data.money.cash = 0
    handle.setCoords(SUSPECT, Config.cuff.distance, 0, 0)
    local ok, err, amount = Police.seizeCash(OFFICER, SUSPECT)
    handle.setCoords(SUSPECT, 0, 0, 0)
    h.assertTrue(ok, tostring(err))
    h.assertEqual(err, nil)
    h.assertEqual(amount, 1000)
    h.assertEqual(handle.players[SUSPECT].data.money.cash, 0)
    h.assertEqual(handle.players[OFFICER].data.money.cash, 1000)
end)

h.report('seize')
