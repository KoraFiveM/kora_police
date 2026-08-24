-- Spike strips. The object itself is created server-side (real networked
-- entity, see server/spikes.lua) -- this file only requests deployment and
-- runs the local tyre-deflate proximity check.

RegisterCommand('spikestrip', function()
    if not Police.isOnDuty() then return end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local deployAt = coords + forward * 2.0
    TriggerServerEvent('qbpolice:server:deploySpike', { x = deployAt.x, y = deployAt.y, z = deployAt.z })
end, false)

local activeStrips = {}

RegisterNetEvent('qbpolice:client:spikeDeployed', function(netId, coords)
    activeStrips[netId] = coords
end)
RegisterNetEvent('qbpolice:client:spikeRemoved', function(netId)
    activeStrips[netId] = nil
end)

CreateThread(function()
    while true do
        Wait(500)
        if next(activeStrips) then
            local vehicle = QB.cache.vehicle()
            if vehicle then
                local vCoords = GetEntityCoords(vehicle)
                for _, stripCoords in pairs(activeStrips) do
                    if #(vCoords - vector3(stripCoords.x, stripCoords.y, stripCoords.z)) <= Config.spikes.deflateDistance then
                        for wheel = 0, 5 do SetVehicleTyreBurst(vehicle, wheel, true, 1000.0) end
                    end
                end
            end
        else
            Wait(2000)
        end
    end
end)
