-- Citations: stored on issue, recipient told how to pay, payable via
-- /paycitation or the export; optional Config.Citations.autoDeduct.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/cuff.lua')
dofile('server/bill.lua')

local OFFICER, CIVILIAN = 1, 2
handle.addPlayer(OFFICER, { job = { name = 'police', onduty = true, grade = { level = 1 } } })
handle.addPlayer(CIVILIAN)
handle.setCoords(CIVILIAN, 1.0, 0.0, 0.0)

local function lastMessage(src)
    for i = #handle.notifications, 1, -1 do
        if handle.notifications[i].src == src then return handle.notifications[i].payload.message end
    end
end

h.test('issuing stores the citation and tells the recipient how to pay', function()
    h.assertTrue(Police.bill(OFFICER, CIVILIAN, 250, 'speeding'))
    local list = Police.getCitations(CIVILIAN)
    h.assertEqual(#list, 1)
    h.assertEqual(list[1].amount, 250)
    h.assertEqual(handle.players[CIVILIAN].data.money.bank, 5000, 'bank untouched by default')
    local msg
    for _, n in ipairs(handle.notifications) do if n.src == CIVILIAN then msg = n.payload.message end end
    h.assertTrue(msg:find('/paycitation 1', 1, true) ~= nil, msg)
end)

h.test('/paycitation charges the bank and clears the citation', function()
    handle.Kora.commands.registry.paycitation(CIVILIAN, { '1' })
    h.assertEqual(handle.players[CIVILIAN].data.money.bank, 4750)
    h.assertEqual(#Police.getCitations(CIVILIAN), 0)
end)

h.test('paying with no citation or too little money is refused with a notice', function()
    handle.Kora.commands.registry.paycitation(CIVILIAN, {})
    h.assertEqual(lastMessage(CIVILIAN), 'You have no unpaid citations.')
    Police.bill(OFFICER, CIVILIAN, 9000, 'big')
    local ok = Police.payCitation(CIVILIAN, 2)
    h.assertFalse(ok)
    h.assertEqual(#Police.getCitations(CIVILIAN), 1)
    h.assertFalse(Police.payCitation(CIVILIAN, 99))
end)

h.test('autoDeduct charges immediately and stores nothing', function()
    Config.Citations.autoDeduct = true
    local before = handle.players[CIVILIAN].data.money.bank
    h.assertTrue(Police.bill(OFFICER, CIVILIAN, 100, 'x'))
    h.assertEqual(handle.players[CIVILIAN].data.money.bank, before - 100)
    h.assertEqual(#Police.getCitations(CIVILIAN), 1)
    Config.Citations.autoDeduct = false
end)

h.test('refused cuff/citation actions notify the officer', function()
    handle.players[OFFICER].job.onduty = false
    handle.fireEvent('kora_police:server:cuff', OFFICER, CIVILIAN)
    h.assertEqual(lastMessage(OFFICER), 'You must be an on-duty police officer to do that.')
    handle.fireEvent('kora_police:server:bill', OFFICER, CIVILIAN, 10, 'x')
    h.assertEqual(lastMessage(OFFICER), 'You must be an on-duty police officer to do that.')
    handle.players[OFFICER].job.onduty = true
    handle.setCoords(CIVILIAN, 500.0, 0.0, 0.0)
    handle.fireEvent('kora_police:server:cuff', OFFICER, CIVILIAN)
    h.assertEqual(lastMessage(OFFICER), 'You are too far away.')
end)

h.report('citation')
