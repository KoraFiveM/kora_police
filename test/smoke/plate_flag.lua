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

h.report('plate_flag')
