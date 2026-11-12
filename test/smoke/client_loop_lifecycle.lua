-- Source-level guardrails for client loops that depend on FiveM scheduling.
-- The server smoke harness intentionally does not emulate native client pools,
-- but these assertions prevent regressions back to permanent polling loops.
local h = dofile('test/harness.lua')

local function source(path)
    local file = assert(io.open(path, 'r'))
    local value = file:read('*a')
    file:close()
    return value
end

local spikes = source('client/spikes.lua')
h.test('spike scanning starts only after a deployed strip and stops with the last strip', function()
    h.assertTrue(spikes:find('local function startScan()', 1, true) ~= nil)
    h.assertTrue(spikes:find("RegisterNetEvent('kora_police:client:spikeDeployed'", 1, true) ~= nil)
    h.assertTrue(spikes:find('while next(activeStrips) do', 1, true) ~= nil)
    h.assertTrue(spikes:find("Kora.cache.onChange('vehicle'", 1, true) ~= nil)
    h.assertFalse(spikes:find('while true do', 1, true) ~= nil,
        'spike handling must not retain a permanent idle polling loop')
end)

local plates = source('client/plate_flag.lua')
h.test('ALPR scanning is lifecycle-bound to an on-duty driver', function()
    h.assertTrue(plates:find('local function canScan()', 1, true) ~= nil)
    h.assertTrue(plates:find('while canScan() do', 1, true) ~= nil)
    h.assertTrue(plates:find("Kora.cache.onChange('vehicle'", 1, true) ~= nil)
    h.assertTrue(plates:find("exports.kora_core:onPlayerDataChange({ 'job' }, startScan)", 1, true) ~= nil)
    h.assertFalse(plates:find('while true do', 1, true) ~= nil,
        'ALPR must not retain a permanent idle polling loop')
end)

h.report('client_loop_lifecycle')
