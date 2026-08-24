-- Spike strips. The object itself is created server-side (real networked
-- entity, see server/spikes.lua) -- this file only requests deployment and
-- runs the local tyre-deflate proximity check.

RegisterCommand('spikestrip', function()
    if not Police.isOnDuty() then return end
    local ped = QB.cache.ped()
    local coords = QB.cache.coords()
    local forward = GetEntityForwardVector(ped)
    local deployAt = coords + forward * 2.0
    TriggerServerEvent('qbpolice:server:deploySpike', { x = deployAt.x, y = deployAt.y, z = deployAt.z })
end, false)

local activeStrips = {}
local scanRunning = false

local function startScan()
    if scanRunning or not next(activeStrips) then return end
    scanRunning = true

    CreateThread(function()
        local scans = 0
        while next(activeStrips) do
            local vehicle = QB.cache.vehicle()

            if vehicle then
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
            end

            -- A moving vehicle needs a reasonably quick check. On foot this
            -- thread is still cheap, and it only exists while at least one
            -- networked strip exists anywhere in the session.
            Wait(vehicle and 500 or 1000)
        end

        scanRunning = false
        if Config.performance.diagnostics then
            print(('[qbpolice] spike scanner stopped after %d vehicle scans'):format(scans))
        end
    end)
end

RegisterNetEvent('qbpolice:client:spikeDeployed', function(netId, coords)
    activeStrips[netId] = coords
    startScan()
end)
RegisterNetEvent('qbpolice:client:spikeRemoved', function(netId)
    activeStrips[netId] = nil
end)

QB.cache.onChange('vehicle', function(vehicle)
    if vehicle then startScan() end
end)
