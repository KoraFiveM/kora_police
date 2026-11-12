-- Spike strips. The object itself is created server-side (real networked
-- entity, see server/spikes.lua) -- this file only requests deployment and
-- runs the local tyre-deflate proximity check.

function Police.requestSpikeStrip()
    if not Police.isOnDuty() then return end
    local ped = Kora.cache.ped()
    local coords = Kora.cache.coords()
    local forward = GetEntityForwardVector(ped)
    local deployAt = coords + forward * 2.0
    TriggerServerEvent('kora_police:server:deploySpike', { x = deployAt.x, y = deployAt.y, z = deployAt.z })
end

RegisterCommand('spikestrip', Police.requestSpikeStrip, false)
RegisterNetEvent('police:client:SpawnSpikeStrip', Police.requestSpikeStrip)

local activeStrips = {}
local scanRunning = false

-- Runs only while a strip exists AND this player is in a vehicle: the cache's
-- 'vehicle' edge starts it, and leaving the vehicle (or the last strip going)
-- ends it, so there is no on-foot idle polling.
local function startScan()
    if scanRunning or not next(activeStrips) or not Kora.cache.vehicle() then return end
    scanRunning = true

    CreateThread(function()
        local scans = 0
        while next(activeStrips) do
            local vehicle = Kora.cache.vehicle()
            if not vehicle then break end

            if Config.performance.diagnostics then scans = scans + 1 end
            local vCoords = GetEntityCoords(vehicle)
            local maxDistance = Config.spikes.deflateDistance
            local maxDistanceSq = maxDistance * maxDistance

            for _, stripCoords in pairs(activeStrips) do
                local dx = vCoords.x - stripCoords.x
                local dy = vCoords.y - stripCoords.y
                local dz = vCoords.z - stripCoords.z
                if dx * dx + dy * dy + dz * dz <= maxDistanceSq then
                    for wheel = 0, 5 do SetVehicleTyreBurst(vehicle, wheel, true, 1000.0) end
                    break
                end
            end

            -- A moving vehicle needs a reasonably quick check.
            Wait(500)
        end

        scanRunning = false
        if Config.performance.diagnostics then
            print(('[kora_police] spike scanner stopped after %d vehicle scans'):format(scans))
        end
    end)
end

RegisterNetEvent('kora_police:client:spikeDeployed', function(netId, coords)
    activeStrips[netId] = coords
    -- Only the current network owner grounds the server-created object.
    CreateThread(function()
        local deadline = GetGameTimer() + 5000
        while activeStrips[netId] == coords and GetGameTimer() < deadline do
            local object = NetworkGetEntityFromNetworkId(netId)
            if object ~= 0 and DoesEntityExist(object) and NetworkHasControlOfEntity(object) then
                PlaceObjectOnGroundProperly(object)
                return
            end
            Wait(100)
        end
    end)
    startScan()
end)
RegisterNetEvent('kora_police:client:spikeRemoved', function(netId)
    activeStrips[netId] = nil
end)

-- kora_lib drops every onChange registration when it restarts, so this runs
-- at load and again on its restart; startScan() seeds from the current vehicle.
local function watchVehicle()
    Kora.cache.onChange('vehicle', function(vehicle)
        if vehicle then startScan() end
    end)
    startScan()
end

watchVehicle()
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'kora_lib' then watchVehicle() end
end)
