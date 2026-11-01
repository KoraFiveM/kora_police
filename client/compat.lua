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
    TriggerEvent('qbpolice:client:spikeDeployed', tonumber(netId), coords)
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
