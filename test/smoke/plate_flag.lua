-- Plate flag tracking -- officer-only flag/unflag, isPlateFlagged lookup,
-- and triggerFlaggedPlate's fan-out to on-duty officers.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/plate_flag.lua')

local OFFICER, OFFICER2_OFFDUTY, CIVILIAN = 1, 2, 3

handle.addPlayer(OFFICER, { job = { name = 'police', onduty = true, grade = { level = 1 } } })
handle.addPlayer(OFFICER2_OFFDUTY, { job = { name = 'police', onduty = false, grade = { level = 1 } } })
handle.addPlayer(CIVILIAN, { job = { name = 'unemployed', onduty = false, grade = { level = 1 } } })

h.test('a civilian cannot flag a plate', function()
    local ok, err = Police.flagPlate(CIVILIAN, 'ABC123', 'stolen')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    h.assertFalse((Police.isPlateFlagged('ABC123')))
end)

h.test('an on-duty officer can flag a plate', function()
    local ok = Police.flagPlate(OFFICER, 'abc123', 'stolen')
    h.assertTrue(ok)
    local flagged, entry = Police.isPlateFlagged('ABC123')
    h.assertTrue(flagged, 'plate lookup should be case-insensitive')
    h.assertEqual(entry.reason, 'stolen')
    h.assertEqual(entry.flaggedBy, OFFICER)
end)

h.test('an unflagged plate reports false', function()
    local flagged = Police.isPlateFlagged('ZZZ999')
    h.assertFalse(flagged)
end)

h.test('an on-duty officer can unflag a plate', function()
    local ok = Police.unflagPlate(OFFICER, 'ABC123')
    h.assertTrue(ok)
    h.assertFalse((Police.isPlateFlagged('ABC123')))
end)

h.test('unflagging a plate that was never flagged fails', function()
    local ok, err = Police.unflagPlate(OFFICER, 'NEVERFLAGGED')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('triggerFlaggedPlate notifies only on-duty officers', function()
    Police.flagPlate(OFFICER, 'BOLO001', 'wanted')
    Police.triggerFlaggedPlate(OFFICER, 'BOLO001')

    local hits = handle.clientEventsFor('qbpolice:client:flaggedPlateTriggered')
    local targets = {}
    for _, e in ipairs(hits) do targets[e.target] = true end
    h.assertTrue(targets[OFFICER], 'on-duty officer should be notified')
    h.assertFalse(targets[OFFICER2_OFFDUTY] == true, 'off-duty officer should not be notified')
end)

h.test('triggerFlaggedPlate is a no-op for an unflagged plate', function()
    local before = #handle.clientEventsFor('qbpolice:client:flaggedPlateTriggered')
    Police.triggerFlaggedPlate(OFFICER, 'NOTFLAGGED')
    local after = #handle.clientEventsFor('qbpolice:client:flaggedPlateTriggered')
    h.assertEqual(after, before)
end)

h.test('flagging mirrors an active vehicle BOLO into kora_mdt and unflagging resolves it', function()
    handle.resourceStates.kora_mdt = 'started'
    local calls = {}
    Kora.sql = {
        single = function() return nil end,
        insert = function(q, args) calls[#calls + 1] = { 'insert', q, args }; return 5 end,
        update = function(q, args) calls[#calls + 1] = { 'update', q, args }; return 1 end,
    }
    h.assertTrue(Police.flagPlate(OFFICER, 'mdt 123 ', 'robbery'))
    h.assertEqual(calls[1][1], 'insert'); h.assertTrue(calls[1][2]:find('kora_mdt_bolos', 1, true) ~= nil)
    h.assertEqual(calls[1][3][1], 'MDT 123')
    h.assertTrue((Police.isPlateFlagged('MDT 123 ')), 'padded plate resolves to the trimmed flag')
    Police.plateFlags['MDT 123'] = nil
    h.assertTrue(Police.unflagPlate(OFFICER, 'MDT 123'), 'unflag succeeds on an MDT-only BOLO')
    h.assertEqual(calls[2][1], 'update'); h.assertTrue(calls[2][2]:find("'resolved'", 1, true) ~= nil)
    Config.plateFlags.mirrorToMdt = false; calls = {}
    Police.flagPlate(OFFICER, 'NOMDT1', 'x'); h.assertEqual(#calls, 0)
    Config.plateFlags.mirrorToMdt = true; handle.resourceStates.kora_mdt = nil; Kora.sql = nil
    h.assertTrue(Police.flagPlate(OFFICER, 'NOMDT2', 'x'), 'works without kora_mdt')
end)

h.report('plate_flag')
