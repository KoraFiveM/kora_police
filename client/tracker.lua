-- GPS tracker: officer attaches one, then that suspect's own client answers
-- periodic location pings; every on-duty officer receives the position.

RegisterNetEvent('qbpolice:client:requestTrackerPing', function()
    TriggerServerEvent('qbpolice:server:sendTrackerLocation')
end)

Police.trackerBlips = Police.trackerBlips or {}

local function upsertTrackerBlip(targetServerId, coords)
    local blip = Police.trackerBlips[targetServerId]
    if blip then
        SetBlipCoords(blip, coords.x, coords.y, coords.z)
        return
    end
    blip = QB.blips.create(coords, {
        sprite = 8,
        color = 1,
        scale = 0.9,
        category = 'Vehicle Tracking',
        name = tostring(targetServerId),
        info = {
            title = 'Active tracker',
            rows = {
                { kind = 'name', label = 'Target ID', value = targetServerId },
                { kind = 'wrappedText', value = 'Location updates as the tracked target moves.' },
            },
        },
    })
    if blip then Police.trackerBlips[targetServerId] = blip end
end

RegisterNetEvent('qbpolice:client:trackerLocation', function(targetServerId, coords)
    upsertTrackerBlip(targetServerId, coords)
end)
RegisterNetEvent('police:client:SendTrackerLocation', function(targetServerId, coords)
    upsertTrackerBlip(targetServerId, coords)
end)
RegisterNetEvent('police:client:TrackerMessage', function(_, message)
    Police.notify(message, 'info')
end)

local function registerTrackerTargets()
    Police.target.reset('tracker')
    Police.target.global('tracker', 'player', {
        {
            label = 'Attach Tracker',
            icon = 'radar',
            canInteract = function(entity)
                return Police.isOnDuty() and IsPedCuffed(entity)
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:setTracker', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)), true)
            end,
        },
    }, Config.cuff.distance)
end
registerTrackerTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerTrackerTargets() end
end)
