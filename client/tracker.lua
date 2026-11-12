-- GPS tracker: officer attaches one, then that suspect's own client answers
-- periodic location pings; every on-duty officer receives the position.

RegisterNetEvent('kora_police:client:requestTrackerPing', function()
    TriggerServerEvent('kora_police:server:sendTrackerLocation')
end)

Police.trackerBlips = Police.trackerBlips or {}

local function upsertTrackerBlip(targetServerId, coords)
    local blip = Police.trackerBlips[targetServerId]
    if blip then
        SetBlipCoords(blip, coords.x, coords.y, coords.z)
        return
    end
    blip = Kora.blips.create(coords, {
        sprite = 8,
        color = 1,
        scale = 0.9,
        category = 'Vehicle Tracking',
        name = tostring(targetServerId),
        info = {
            title = Kora.lang('Notify.active_tracker'),
            rows = {
                { kind = 'name', label = Kora.lang('Notify.target_id'), value = targetServerId },
                { kind = 'wrappedText', value = 'Location updates as the tracked target moves.' },
            },
        },
    })
    if blip then Police.trackerBlips[targetServerId] = blip end
end

RegisterNetEvent('kora_police:client:trackerLocation', function(targetServerId, coords)
    upsertTrackerBlip(targetServerId, coords)
end)
-- Stock sends the tracked player a bare request id (they answer with
-- police:server:SendTrackerLocation); kora's own fan-out sends officers
-- (targetServerId, coords). The two are told apart by the second argument.
RegisterNetEvent('police:client:SendTrackerLocation', function(first, coords)
    if coords == nil then
        local position = GetEntityCoords(PlayerPedId())
        TriggerServerEvent('police:server:SendTrackerLocation', { x = position.x, y = position.y, z = position.z }, first)
        return
    end
    upsertTrackerBlip(first, coords)
end)

local function flashTrackerBlip(coords, message)
    Police.notify(message, 'info')
    if type(coords) ~= 'table' then return end
    local blip = Kora.blips.create(coords, {
        sprite = 458, color = 1, scale = 1.0, category = 'Vehicle Tracking', name = Kora.lang('Notify.anklet_location'),
        info = { title = Kora.lang('Notify.anklet_location'), rows = { { kind = 'wrappedText', value = message } } },
    })
    if blip then SetTimeout(60000, function() Kora.blips.remove(blip) end) end
end

-- Stock payload is (message, coords); kora's own TrackerMessage is (targetId, message).
RegisterNetEvent('police:client:TrackerMessage', function(first, second)
    if type(first) == 'string' then
        flashTrackerBlip(second, first)
    else
        Police.notify(second, 'info')
    end
end)

RegisterNetEvent('police:client:CheckDistance', function()
    local target = Police.closestPlayerServerId(Config.cuff.distance)
    if target then TriggerServerEvent('police:server:SetTracker', target) else Police.notify(Kora.lang('Notify.no_player_nearby'), 'error') end
end)

RegisterNetEvent('police:client:SetTracker', function(active)
    TriggerEvent('qb-clothing:client:loadOutfit', {
        outfitData = { accessory = { item = active and 13 or -1, texture = 0 } },
    })
end)

local function registerTrackerTargets()
    Police.target.reset('tracker')
    Police.target.global('tracker', 'player', {
        {
            label = Kora.lang('Menu.attach_tracker'),
            icon = 'radar',
            canInteract = function(entity)
                return Police.isOnDuty() and Police.isPedCuffed(entity)
            end,
            onSelect = function(entity)
                TriggerServerEvent('kora_police:server:setTracker', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)), true)
            end,
        },
    }, Config.cuff.distance)
end
registerTrackerTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerTrackerTargets() end
end)
