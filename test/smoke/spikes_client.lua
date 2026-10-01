local h = dofile('test/harness.lua')
local events, threads, clock, owner, grounded = {}, {}, 0, true, 0
Config = { spikes = {}, performance = {} }
Police = {}
QB = { cache = { onChange = function() end } }
RegisterCommand = function() end
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
    events['qbpolice:client:spikeDeployed'](1042, { x = 0, y = 0, z = 0 })
    threads[1]()
    h.assertEqual(clock, 200)
    h.assertEqual(grounded, 1)
    owner = false
    local before = #threads
    events['qbpolice:client:spikeDeployed'](1043, { x = 0, y = 0, z = 0 })
    local started = clock
    threads[before + 1]()
    h.assertEqual(clock - started, 5000)
    h.assertEqual(grounded, 1)
    before = #threads
    events['qbpolice:client:spikeDeployed'](1044, { x = 0, y = 0, z = 0 })
    events['qbpolice:client:spikeRemoved'](1044)
    owner = true
    threads[before + 1]()
    h.assertEqual(grounded, 1, 'removed strips are never grounded')
end)
h.report('spikes client')
