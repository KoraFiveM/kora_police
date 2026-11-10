local h = dofile('test/harness.lua')
local events, threads, clock, owner, grounded = {}, {}, 0, true, 0
local cachedVehicle, vehicleHandlers, resourceStartHandlers, bursts = false, {}, {}, 0
Config = { spikes = { deflateDistance = 5.0 }, performance = {} }
Police = {}
Kora = { cache = {
    onChange = function(key, fn) if key == 'vehicle' then vehicleHandlers[#vehicleHandlers + 1] = fn end end,
    vehicle = function() return cachedVehicle end,
} }
RegisterCommand = function() end
AddEventHandler = function(name, fn) if name == 'onClientResourceStart' then resourceStartHandlers[#resourceStartHandlers + 1] = fn end end
GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end
SetVehicleTyreBurst = function() bursts = bursts + 1 end
RegisterNetEvent = function(name, fn) events[name] = fn end
CreateThread = function(fn) threads[#threads + 1] = fn end
GetGameTimer = function() return clock end
Wait = function(ms) clock = clock + ms end
NetworkGetEntityFromNetworkId = function() return clock >= 200 and 42 or 0 end
DoesEntityExist = function(entity) return entity == 42 end
NetworkHasControlOfEntity = function() return owner end
PlaceObjectOnGroundProperly = function(entity) assert(entity == 42); grounded = grounded + 1 end
dofile('client/spikes.lua')

h.test('only the network owner grounds a streamed strip, with a bounded wait', function()
    events['kora_police:client:spikeDeployed'](1042, { x = 0, y = 0, z = 0 })
    threads[1]()
    h.assertEqual(clock, 200)
    h.assertEqual(grounded, 1)
    owner = false
    local before = #threads
    events['kora_police:client:spikeDeployed'](1043, { x = 0, y = 0, z = 0 })
    local started = clock
    threads[before + 1]()
    h.assertEqual(clock - started, 5000)
    h.assertEqual(grounded, 1)
    before = #threads
    events['kora_police:client:spikeDeployed'](1044, { x = 0, y = 0, z = 0 })
    events['kora_police:client:spikeRemoved'](1044)
    owner = true
    threads[before + 1]()
    h.assertEqual(grounded, 1, 'removed strips are never grounded')
end)
h.test('the deflate scan runs only while in a vehicle, started by the vehicle cache edge', function()
    events['kora_police:client:spikeDeployed'](2001, { x = 100, y = 100, z = 0 })
    local before = #threads
    events['kora_police:client:spikeDeployed'](2002, { x = 0, y = 0, z = 0 })
    h.assertEqual(#threads, before + 1, 'on foot: only the grounding thread starts, no scan')

    cachedVehicle = 77
    vehicleHandlers[1](77, false)
    h.assertEqual(#threads, before + 2, 'entering a vehicle starts the scan immediately')
    vehicleHandlers[1](77, false)
    h.assertEqual(#threads, before + 2, 'a second edge does not start a duplicate scan')

    local scan = coroutine.create(threads[before + 2])
    local realWait = Wait
    Wait = function(ms) clock = clock + ms; coroutine.yield() end
    coroutine.resume(scan)
    h.assertEqual(bursts, 6, 'first scan iteration bursts the tyres next to a strip')
    cachedVehicle = false
    coroutine.resume(scan)
    h.assertEqual(coroutine.status(scan), 'dead', 'leaving the vehicle ends the scan')
    Wait = realWait

    cachedVehicle = 78
    resourceStartHandlers[1]('kora_lib')
    h.assertEqual(#vehicleHandlers, 2, 'a kora_lib restart re-registers the listener')
    h.assertEqual(#threads, before + 3, 're-registration seeds an already-seated player')
end)
h.report('spikes client')
