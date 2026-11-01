-- Remaining `police:client:*` legacy listeners not naturally owned by a more
-- specific file. Most of the checklist's other legacy names are handled
-- directly where the matching feature lives (cuff.lua, escort.lua,
-- search.lua, dispatch.lua, tracker.lua, fingerprint.lua, plate_flag.lua,
-- spikes.lua) so third-party scripts see event-name parity without a second
-- forwarding hop.

RegisterNetEvent('police:client:SearchPlayer', function(targetServerId)
    exports.kora_inventory:openInventory('player', targetServerId)
end)

RegisterNetEvent('police:client:SyncSpikes', function(netId, active)
    if active == false then TriggerEvent('qbpolice:client:spikeRemoved', tonumber(netId)) end
end)
RegisterNetEvent('police:client:spawnObject', function(netId, coords)
    if type(coords) == 'table' then TriggerEvent('qbpolice:client:spikeDeployed', tonumber(netId), coords) end
end)

-- `GetEscorted`/`GetKidnappedTarget`/`GetKidnappedDragger` are server
-- callbacks (see server/compat/police.lua); no client-side mirror is needed
-- since Police.escortedTarget/draggedTarget already track this resource's
-- own local state.

-- Stock qb-policejob client interaction events -----------------------------
--
-- qb-radialmenu (and other stock scripts) fire these with TriggerEvent on the
-- local client. Each initiator picks the nearest player within
-- Config.cuff.distance and asks the server through the stock `police:server:*`
-- name, which server/compat/police.lua forwards onto the Police.* functions:
-- the server alone checks job/duty/distance/cuff state, so nothing here can
-- cuff, search or move anyone the native flow would refuse.

local function nearestTarget()
    local target = Police.closestPlayerServerId(Config.cuff.distance)
    if not target then Police.notify('No player nearby.', 'error') end
    return target
end

local function onNearest(serverEvent)
    return function()
        local target = nearestTarget()
        if target then TriggerServerEvent(serverEvent, target) end
    end
end

RegisterNetEvent('police:client:CuffPlayer', onNearest('police:server:CuffPlayer'))
-- Stock "soft" cuffing needs no item; kora's soft cuff is the handcuffs-item
-- flow, which finds its own target server-side.
RegisterNetEvent('police:client:CuffPlayerSoft', function()
    TriggerServerEvent('police:server:CuffPlayerSoft')
end)
RegisterNetEvent('police:client:SeizeCash', onNearest('police:server:SeizeCash'))
RegisterNetEvent('police:client:SeizeDriverLicense', onNearest('police:server:SeizeDriverLicense'))
RegisterNetEvent('police:client:RobPlayer', onNearest('police:server:RobPlayer'))
RegisterNetEvent('police:client:PutPlayerInVehicle', onNearest('police:server:PutPlayerInVehicle'))
RegisterNetEvent('police:client:SetPlayerOutVehicle', onNearest('police:server:SetPlayerOutVehicle'))

-- Stock fires the escort/drag initiators again to release.
RegisterNetEvent('police:client:EscortPlayer', function()
    if Police.escortedTarget then
        TriggerServerEvent('qbpolice:server:deEscort', Police.escortedTarget)
        return
    end
    local target = nearestTarget()
    if target then TriggerServerEvent('police:server:EscortPlayer', target) end
end)
RegisterNetEvent('police:client:KidnapPlayer', function()
    if Police.draggedTarget then
        TriggerServerEvent('qbpolice:server:stopDrag', Police.draggedTarget)
        return
    end
    local target = nearestTarget()
    if target then TriggerServerEvent('police:server:KidnapPlayer', target) end
end)

RegisterNetEvent('police:client:JailPlayer', function()
    local target = nearestTarget()
    if not target then return end
    local result = Kora.nui.openInputDialog({
        { id = 'minutes', label = 'Minutes', type = 'number', default = Config.jail.defaultMinutes, min = 1, required = true },
        { id = 'reason', label = 'Reason', type = 'text' },
    }, 'Book Suspect')
    if not result or not result.values then return end
    TriggerServerEvent('police:server:JailPlayer', target, result.values.minutes, result.values.reason)
end)

RegisterNetEvent('police:client:BillPlayer', function()
    local target = nearestTarget()
    if not target then return end
    local result = Kora.nui.openInputDialog({
        { id = 'amount', label = 'Fine Amount', type = 'number', default = Config.fine.tiers[1][1], min = 1, required = true },
        { id = 'reason', label = 'Reason', type = 'text' },
    }, 'Issue Citation')
    if not result or not result.values then return end
    TriggerServerEvent('police:server:BillPlayer', target, result.values.amount, result.values.reason)
end)

-- Stock "victim side" events. In stock the server tells the affected player's
-- client to cuff / attach / seat itself and the client then reports back. Kora
-- never lets a client set those states: the server validates, then drives the
-- native `qbpolice:client:*` events. Honouring these would let any script (or
-- cheat) cuff, drag or seat the local player without a server check, so they
-- only tell the player they are unsupported (at most once every 5s per event).
local lastUnsupportedAt = {}
local function unsupported(eventName)
    RegisterNetEvent(eventName, function()
        local now = GetGameTimer()
        if lastUnsupportedAt[eventName] and now - lastUnsupportedAt[eventName] < 5000 then return end
        lastUnsupportedAt[eventName] = now
        Police.notify(('%s is not supported by kora_police.'):format(eventName), 'error')
    end)
end
for _, eventName in ipairs({
    'police:client:GetCuffed', 'police:client:GetEscorted', 'police:client:DeEscort',
    'police:client:GetKidnappedTarget', 'police:client:GetKidnappedDragger',
    'police:client:PutInVehicle', 'police:client:SetOutVehicle',
}) do unsupported(eventName) end

-- Stock job events with no safe client-side equivalent: jailing and vehicle
-- spawning are server-owned here, and the garage menus belong to qb-menu.
for _, eventName in ipairs({
    'police:client:SendToJail', 'police:client:TakeOutVehicle', 'police:client:VehicleMenuHeader',
    'police:client:ImpoundMenuHeader', 'qb-police:client:spawnHelicopter',
}) do unsupported(eventName) end

-- Server broadcasts kora has no client for (duty blips are kora_dispatch's job),
-- registered so a third-party TriggerClientEvent is accepted silently.
for _, eventName in ipairs({
    'police:client:UpdateBlips', 'police:client:SendEmergencyMessage', 'police:client:CallAnim',
}) do RegisterNetEvent(eventName, function() end) end

RegisterNetEvent('police:client:EmergencySound', function()
    PlaySound(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', 0, 0, 1)
end)

-- Stock job events other resources trigger (radial menu, commands, heists) --

-- The panic button: kora raises the officer-down call to LEO and EMS server-side.
RegisterNetEvent('police:client:SendPoliceEmergencyAlert', function()
    if not Police.isOnDuty() then return end
    TriggerServerEvent('qbpolice:server:panic')
end)

-- Stock arguments are (coords, text); kora_core's legacy dispatch fan-out sends (text, coords).
RegisterNetEvent('police:client:policeAlert', function(first, second)
    local coords, text = first, second
    if type(first) == 'string' then coords, text = second, first end
    if type(text) ~= 'string' then return end
    Police.notify(text, 'info')
    if type(coords) ~= 'table' then return end
    local blip = Kora.blips.create(coords, {
        sprite = 60, color = 1, scale = 0.8, category = 'Police', name = text,
        info = { title = 'Police alert', rows = { { kind = 'wrappedText', value = text } } },
    })
    if blip then SetTimeout(60000, function() Kora.blips.remove(blip) end) end
end)

RegisterNetEvent('police:client:CheckStatus', function()
    if not Police.isOnDuty() then return end
    local target = Police.closestPlayerServerId(5.0)
    if not target then return Police.notify('No player nearby.', 'error') end
    local statuses = Kora.callback.trigger('police:GetPlayerStatus', target)
    for _, text in ipairs(type(statuses) == 'table' and statuses or {}) do Police.notify(text, 'info') end
end)

RegisterNetEvent('qb-police:client:scanFingerPrint', function()
    local target = Police.closestPlayerServerId(Config.cuff.distance)
    if target then TriggerServerEvent('police:server:showFingerprint', target) else Police.notify('No player nearby.', 'error') end
end)

RegisterNetEvent('qb-policejob:ToggleDuty', function()
    Kora.events.trigger('qbpolice:server:toggleDuty')
end)

RegisterNetEvent('police:client:ImpoundVehicle', function(fullImpound, price)
    if not Police.isOnDuty() then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    local origin = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(origin.x, origin.y, origin.z, 5.0, 0, 71)
    if not vehicle or vehicle == 0 then return Police.notify('No vehicle nearby.', 'error') end
    local completed = Kora.progressbar.start({
        label = 'Impounding...',
        duration = 5000,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'missheistdockssetup1clipboard@base', clip = 'base', flag = 1 },
    })
    if not completed then return Police.notify('Cancelled.', 'error') end
    local plate = (GetVehicleNumberPlateText(vehicle) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    TriggerServerEvent('police:server:Impound', plate, fullImpound, price)
end)

-- Stock hands the impound menu's chosen row (`data.vehicle.plate`); the lot is
-- the nearest configured one, which the server re-checks.
RegisterNetEvent('police:client:TakeOutImpound', function(data)
    local plate = type(data) == 'table' and type(data.vehicle) == 'table' and data.vehicle.plate
    if type(plate) ~= 'string' then return end
    local origin = GetEntityCoords(PlayerPedId())
    local best, bestDistance
    for index, lot in ipairs(Config.impound.lots) do
        local distance = #(origin - vector3(lot.coords.x, lot.coords.y, lot.coords.z))
        if not bestDistance or distance < bestDistance then best, bestDistance = index, distance end
    end
    if best then TriggerServerEvent('police:server:TakeOutImpound', plate, best) end
end)

RegisterNetEvent('police:client:EvidenceStashDrawer', function()
    local origin = GetEntityCoords(PlayerPedId())
    local room
    for index, point in ipairs(Config.evidence.drawers.rooms) do
        if #(origin - vector3(point.x, point.y, point.z)) < Config.evidence.drawers.distance then room = index end
    end
    if not room then return end
    local result = Kora.nui.openInputDialog({
        { id = 'slot', label = 'Slot no. (1,2,3)', type = 'number', min = 1, max = Config.evidence.drawers.maxDrawer, required = true },
    }, ('Evidence Stash | %d'):format(room))
    local slot = result and result.values and tonumber(result.values.slot)
    if slot then TriggerServerEvent('qb-policejob:server:evidence', ('%d | Drawer %d'):format(room, slot)) end
end)

RegisterNetEvent('heli:client:spotlight', function(serverId, state)
    local player = GetPlayerFromServerId(serverId)
    if not player or player == -1 then return end
    local vehicle = GetVehiclePedIsIn(GetPlayerPed(player), false)
    if vehicle and vehicle ~= 0 then SetVehicleSearchlight(vehicle, state == true, false) end
end)
