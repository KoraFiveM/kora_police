-- The stock qb-policejob client interaction events (the 18 in
-- client/interactions.lua) must all be registered, forward to server-validated
-- events only, and never change local cuff/escort state themselves.
local h = dofile('test/harness.lua')

local handlers, serverEvents, notifications = {}, {}, {}
local nearest, now = 9, 0
function RegisterNetEvent(name, cb) if cb then handlers[name] = cb end end
function TriggerServerEvent(name, ...) serverEvents[#serverEvents + 1] = { name = name, args = { ... } } end
function GetGameTimer() now = now + 10000; return now end
Config = { cuff = { distance = 2.5 }, jail = { defaultMinutes = 10 }, fine = { tiers = { { 100 } } } }
Police = { notify = function(message) notifications[#notifications + 1] = message end,
    closestPlayerServerId = function() return nearest end }
Kora = { nui = { openInputDialog = function() return { values = { minutes = 7, amount = 250, reason = 'r' } } end } }
dofile('client/compat.lua')

local STOCK = { 'CuffPlayer', 'CuffPlayerSoft', 'GetCuffed', 'EscortPlayer', 'PutPlayerInVehicle',
    'SetPlayerOutVehicle', 'SeizeCash', 'SeizeDriverLicense', 'RobPlayer', 'JailPlayer', 'BillPlayer',
    'KidnapPlayer', 'GetEscorted', 'DeEscort', 'GetKidnappedTarget', 'GetKidnappedDragger',
    'PutInVehicle', 'SetOutVehicle' }

local function fire(name, ...)
    serverEvents = {}
    handlers['police:client:' .. name](...)
    return serverEvents
end

h.test('all 18 stock interaction events are registered', function()
    h.assertEqual(#STOCK, 18)
    for _, name in ipairs(STOCK) do h.assertTrue(handlers['police:client:' .. name] ~= nil, name) end
end)

h.test('initiators forward the nearest player to the stock server event', function()
    for client, server in pairs({ CuffPlayer = 'CuffPlayer', SeizeCash = 'SeizeCash',
        SeizeDriverLicense = 'SeizeDriverLicense', RobPlayer = 'RobPlayer',
        PutPlayerInVehicle = 'PutPlayerInVehicle', SetPlayerOutVehicle = 'SetPlayerOutVehicle',
        EscortPlayer = 'EscortPlayer', KidnapPlayer = 'KidnapPlayer' }) do
        local sent = fire(client)
        h.assertEqual(#sent, 1, client)
        h.assertEqual(sent[1].name, 'police:server:' .. server)
        h.assertEqual(sent[1].args[1], 9)
    end
    h.assertEqual(fire('CuffPlayerSoft')[1].name, 'police:server:CuffPlayerSoft')
end)

h.test('jail and bill collect input first and send server-validated values', function()
    local jail = fire('JailPlayer')[1]
    h.assertEqual(jail.name, 'police:server:JailPlayer')
    h.assertEqual(jail.args[2], 7)
    local bill = fire('BillPlayer')[1]
    h.assertEqual(bill.name, 'police:server:BillPlayer')
    h.assertEqual(bill.args[2], 250)
end)

h.test('nothing is sent when nobody is in reach', function()
    nearest = nil
    for _, name in ipairs({ 'CuffPlayer', 'EscortPlayer', 'JailPlayer', 'BillPlayer', 'RobPlayer' }) do
        h.assertEqual(#fire(name), 0, name)
    end
    nearest = 9
end)

h.test('escort and drag initiators release the current target instead', function()
    Police.escortedTarget, Police.draggedTarget = 12, 13
    local escort = fire('EscortPlayer')[1]
    h.assertEqual(escort.name, 'kora_police:server:deEscort')
    h.assertEqual(escort.args[1], 12)
    local drag = fire('KidnapPlayer')[1]
    h.assertEqual(drag.name, 'kora_police:server:stopDrag')
    h.assertEqual(drag.args[1], 13)
    Police.escortedTarget, Police.draggedTarget = nil, nil
end)

h.test('victim-side events send nothing, change nothing and only notify', function()
    for _, name in ipairs({ 'GetCuffed', 'GetEscorted', 'DeEscort', 'GetKidnappedTarget',
        'GetKidnappedDragger', 'PutInVehicle', 'SetOutVehicle' }) do
        notifications = {}
        h.assertEqual(#fire(name, 3, true), 0, name)
        h.assertEqual(#notifications, 1, name)
    end
    h.assertEqual(Police.cuffed, nil)
end)

h.report('stock_client_events')
