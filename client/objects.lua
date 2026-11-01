-- Road props (cones, barriers, signs, tents, lights): the stock radial-menu
-- events run the placement animation, then ask the server to create the prop at
-- the officer's position (server/objects.lua).

local function progress(label, anim)
    return Kora.progressbar.start({
        label = label,
        duration = 2500,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = anim,
    })
end

local function placeObject(objectType)
    return function()
        if not Police.isOnDuty() then return end
        local completed = progress('Placing object...', { dict = 'anim@narcotics@trash', clip = 'drop_front', flag = 16 })
        if completed then TriggerServerEvent('police:server:spawnObject', objectType) end
    end
end

RegisterNetEvent('police:client:spawnCone', placeObject('cone'))
RegisterNetEvent('police:client:spawnBarrier', placeObject('barrier'))
RegisterNetEvent('police:client:spawnRoadSign', placeObject('roadsign'))
RegisterNetEvent('police:client:spawnTent', placeObject('tent'))
RegisterNetEvent('police:client:spawnLight', placeObject('light'))

RegisterNetEvent('police:client:deleteObject', function()
    if not Police.isOnDuty() then return end
    local completed = progress('Removing object...', {
        dict = 'weapons@first_person@aim_rng@generic@projectile@thermal_charge@', clip = 'plant_floor', flag = 16,
    })
    if completed then TriggerServerEvent('qbpolice:server:deleteNearestObject') end
end)

RegisterNetEvent('police:client:removeObject', function() end)

-- Only the current network owner can ground a server-created prop.
RegisterNetEvent('qbpolice:client:objectPlaced', function(_, netId)
    CreateThread(function()
        local deadline = GetGameTimer() + 5000
        while GetGameTimer() < deadline do
            local object = NetworkGetEntityFromNetworkId(netId)
            if object ~= 0 and DoesEntityExist(object) and NetworkHasControlOfEntity(object) then
                PlaceObjectOnGroundProperly(object)
                return
            end
            Wait(100)
        end
    end)
end)
