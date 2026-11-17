-- Impound shows a cancellable progress bar and only reaches the server once it completes.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')

local result, started, sent = true, nil, {}
Police = { notify = function() end, isOnDuty = function() return true end, target = { reset = function() end, global = function(_, _, options) Police.impoundOption = options[1] end, sphere = function() end } }
Kora.progressbar = { start = function(payload) started = payload; return result end }
_G.DoesEntityExist = function() return true end
_G.DeleteEntity = function() end
_G.GetVehicleNumberPlateText = function() return 'ABC123' end
_G.TriggerServerEvent = function(name, ...) sent[#sent + 1] = { name = name, args = { ... } } end
_G.AddEventHandler = function() end
dofile('client/impound.lua')

h.test('impound waits for the progress bar with an animation', function()
    sent = {}; result = true
    Police.impoundOption.onSelect(1)
    h.assertEqual(started.duration, Config.impound.progress.duration)
    h.assertTrue(started.canCancel); h.assertTrue(started.anim ~= nil and started.anim.dict ~= nil)
    h.assertEqual(sent[1].name, 'kora_police:server:impound')
end)

h.test('cancelling the progress bar does not impound', function()
    sent = {}; result = false
    Police.impoundOption.onSelect(1)
    h.assertEqual(#sent, 0)
end)

h.test('progress disabled impounds instantly', function()
    sent = {}; started = nil; Config.impound.progress.enabled = false
    Police.impoundOption.onSelect(1)
    h.assertTrue(started == nil); h.assertEqual(#sent, 1)
end)

h.test('a progress bar that cannot start names the reason in the message', function()
    sent = {}; Config.impound.progress.enabled = true
    local notice
    Police.notify = function(message) notice = message end
    Kora.progressbar.start = function() error('busy', 0) end
    Police.impoundOption.onSelect(1)
    h.assertEqual(notice, 'Impound progress could not start: busy')
    h.assertEqual(#sent, 0)
end)

h.report('impound_progress')
