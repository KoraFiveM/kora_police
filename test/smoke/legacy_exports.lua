local h = dofile('test/harness.lua')
local events, native = {}, {}
AddEventHandler = function(name, fn) events[name] = fn end
RegisterNetEvent = function(name, fn) events[name] = fn end
exports = function(name, fn) native[name] = fn end
TriggerEvent = function() end
QB = { compat = dofile('../kora_lib/compat/provider.lua')() }
dofile('client/core.lua')

h.test('stock IsHandcuffed export uses the native cuff state and retains lowercase callers', function()
    local legacy
    assert(events['__cfx_export_qb-policejob_IsHandcuffed'])(function(fn) legacy = fn end)
    h.assertEqual(legacy, native.IsHandcuffed)
    h.assertEqual(legacy, native.isHandcuffed)
    h.assertFalse(legacy())
    events['qbpolice:client:cuffed'](true, false, 1)
    h.assertTrue(legacy())
    events['qbpolice:client:cuffed'](false, false, 1)
    h.assertFalse(legacy())
end)

h.report('legacy_exports')
