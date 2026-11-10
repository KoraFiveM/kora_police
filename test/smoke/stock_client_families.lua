-- Stock client event families other resources trigger: road props, spike radial
-- item, security cameras, job events, evidence status. All of them must only ask
-- the server (or render locally) and never change authoritative state.
local h = dofile('test/harness.lua')

local handlers, serverEvents, notifications, threads = {}, {}, {}, {}
local onDuty, progressResult, nearest = true, true, 9
local cams = {}
function RegisterNetEvent(name, cb) if cb then handlers[name] = cb end end
function AddEventHandler() end
function RegisterCommand() end
function TriggerServerEvent(name, ...) serverEvents[#serverEvents + 1] = { name = name, args = { ... } } end
function TriggerEvent() end
function CreateThread(fn) threads[#threads + 1] = fn end
function Wait() end
function SetTimeout() end
function GetGameTimer() return 0 end
function GetCurrentResourceName() return 'kora_police' end
function PlayerPedId() return 1 end
function GetEntityCoords() return vector3(0.0, 0.0, 0.0) end
function IsPedInAnyVehicle() return false end
function GetClosestVehicle() return 55 end
function GetVehicleNumberPlateText() return ' PLATE1 ' end
local V = {}
V.__mul = function(a, k) return setmetatable({ x = a.x * k, y = a.y * k, z = a.z * k }, V) end
V.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, V) end
V.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
function CreateCam() cams.created = true; return 5 end
function SetCamCoord() end
function SetCamRot() end
function SetFocusArea() end
function RenderScriptCams() end
function SetTimecycleModifier() end
function SetTimecycleModifierStrength() end
function DoScreenFadeOut() end
function DoScreenFadeIn() end
function IsScreenFadedOut() return true end
function DisplayRadar() end
function DestroyCam() cams.destroyed = true end
function ClearTimecycleModifier() end
function SetFocusEntity() end
function PlaySound() end
function GetPlayerFromServerId() return 1 end
function GetPlayerPed() return 1 end
function GetVehiclePedIsIn() return 66 end
local searchlight
function SetVehicleSearchlight(v, state) searchlight = { v, state } end
Config = {
    cuff = { distance = 2.5 }, cameras = { hideRadar = false, list = {
        [1] = { label = 'Cam 1', coords = { x = 1, y = 2, z = 3 }, r = { x = 0, y = 0, z = 0 }, isOnline = true, canRotate = false } } },
    impound = { lots = { { coords = { x = 100.0, y = 0.0, z = 0.0 } } } },
    evidence = { drawers = { rooms = { { x = 0.0, y = 0.0, z = 0.0 } }, distance = 3.0, maxDrawer = 20 },
        statuses = { alcohol = 'Smells like alcohol' }, clearDistance = 10.0 },
    spikes = {},
}
Police = {
    isOnDuty = function() return onDuty end,
    target = { reset = function() end, global = function() end },
    notify = function(message) notifications[#notifications + 1] = message end,
    closestPlayerServerId = function() return nearest end,
}
Kora = {
    progressbar = { start = function() return progressResult end },
    cache = { onChange = function() end, ped = function() return 1 end, coords = function() return vector3(0, 0, 0) end },
    callback = { trigger = function() return { 'Red hands', 'Confused' } end },
    events = { trigger = function(name) serverEvents[#serverEvents + 1] = { name = name, args = {} } end },
    nui = { openInputDialog = function() return { values = { slot = 3 } } end },
    blips = { create = function() return 1 end, remove = function() end },
}
function GetEntityForwardVector() return vector3(0, 1, 0) end
getmetatable = getmetatable
dofile('client/spikes.lua')
dofile('client/objects.lua')
dofile('client/camera.lua')
dofile('client/tracker.lua')
dofile('client/compat.lua')

local function fire(name, ...)
    serverEvents = {}
    handlers[name](...)
    return serverEvents
end

h.test('radial prop events place objects through the server once the bar completes', function()
    for event, objectType in pairs({ spawnCone = 'cone', spawnBarrier = 'barrier', spawnRoadSign = 'roadsign',
        spawnTent = 'tent', spawnLight = 'light' }) do
        local sent = fire('police:client:' .. event)
        h.assertEqual(sent[1].name, 'police:server:spawnObject')
        h.assertEqual(sent[1].args[1], objectType)
    end
    progressResult = false
    h.assertEqual(#fire('police:client:spawnCone'), 0)
    h.assertEqual(#fire('police:client:deleteObject'), 0)
    progressResult = true
    h.assertEqual(fire('police:client:deleteObject')[1].name, 'kora_police:server:deleteNearestObject')
    onDuty = false
    h.assertEqual(#fire('police:client:spawnCone'), 0)
    onDuty = true
end)

h.test('SpawnSpikeStrip asks the server to deploy, nothing is created locally', function()
    local sent = fire('police:client:SpawnSpikeStrip')
    h.assertEqual(sent[1].name, 'kora_police:server:deploySpike')
end)

h.test('stock spawnObject payload does not corrupt the spike scanner', function()
    handlers['police:client:spawnObject'](10001, 'cone', 3)
end)

h.test('cameras open only while on duty, honour offline flags and close with 0', function()
    onDuty = false
    handlers['police:client:ActiveCamera'](1)
    h.assertEqual(cams.created, nil)
    onDuty = true
    handlers['police:client:SetCamera'](1, false)
    handlers['police:client:ActiveCamera'](1)
    h.assertEqual(cams.created, nil)
    handlers['police:client:EnableAllCameras']()
    handlers['police:client:ActiveCamera'](1)
    h.assertTrue(cams.created)
    handlers['police:client:ActiveCamera'](0)
    h.assertTrue(cams.destroyed)
    handlers['police:client:ActiveCamera'](99)
    handlers['police:client:SetCamera']({ 1, 99 }, false)
end)

h.test('policeAlert accepts both stock (coords, text) and kora_core (text, coords) orders', function()
    notifications = {}
    handlers['police:client:policeAlert']({ x = 1, y = 2, z = 3 }, 'Stock')
    handlers['police:client:policeAlert']('Core', { x = 1, y = 2, z = 3 })
    handlers['police:client:policeAlert']({ x = 1 }, nil)
    h.assertEqual(notifications[1], 'Stock')
    h.assertEqual(notifications[2], 'Core')
    h.assertEqual(#notifications, 2)
end)

h.test('job events route onto kora flows', function()
    h.assertEqual(fire('police:client:SendPoliceEmergencyAlert')[1].name, 'kora_police:server:panic')
    h.assertEqual(fire('qb-police:client:scanFingerPrint')[1].name, 'police:server:showFingerprint')
    h.assertEqual(fire('police:client:CheckDistance')[1].name, 'police:server:SetTracker')
    h.assertEqual(fire('qb-policejob:ToggleDuty')[1].name, 'kora_police:server:toggleDuty')
    local impound = fire('police:client:ImpoundVehicle', true, 50)[1]
    h.assertEqual(impound.name, 'police:server:Impound')
    h.assertEqual(impound.args[1], 'PLATE1')
    h.assertEqual(impound.args[2], true)
    local takeOut = fire('police:client:TakeOutImpound', { vehicle = { plate = 'ABC' } })[1]
    h.assertEqual(takeOut.name, 'police:server:TakeOutImpound')
    h.assertEqual(takeOut.args[2], 1)
    h.assertEqual(#fire('police:client:TakeOutImpound', {}), 0)
    local drawer = fire('police:client:EvidenceStashDrawer')[1]
    h.assertEqual(drawer.name, 'qb-policejob:server:evidence')
    h.assertEqual(drawer.args[1], '1 | Drawer 3')
    notifications = {}
    h.assertEqual(#fire('police:client:CheckStatus'), 0)
    h.assertEqual(notifications[2], 'Confused')
end)

h.test('unsupported job events notify and send nothing', function()
    for _, name in ipairs({ 'police:client:SendToJail', 'police:client:TakeOutVehicle',
        'police:client:VehicleMenuHeader', 'police:client:ImpoundMenuHeader', 'qb-police:client:spawnHelicopter' }) do
        notifications = {}
        h.assertEqual(#fire(name, 5), 0, name)
        h.assertEqual(#notifications, 1, name)
    end
    h.assertTrue(handlers['police:client:UpdateBlips'] ~= nil)
end)

h.test('heli spotlight renders on the named player\'s helicopter', function()
    handlers['heli:client:spotlight'](4, true)
    h.assertEqual(searchlight[1], 66)
    h.assertEqual(searchlight[2], true)
end)

h.report('stock_client_families')
