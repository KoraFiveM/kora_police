-- Put a cuffed suspect (currently being escorted or dragged) into a nearby
-- vehicle, or take them back out. The seating itself is done on the
-- SUSPECT's own client (server relay), same reasoning as escort/drag.

RegisterNetEvent('qbpolice:client:putInVehicle', function(netId, seat)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 then return end
    if IsEntityAttached(PlayerPedId()) then DetachEntity(PlayerPedId(), true, true) end
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, seat or -1)
end)

RegisterNetEvent('qbpolice:client:takeOutVehicle', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 0)
    end
end)

local function registerVehicleTargets()
    Police.target.reset('vehicle')
    Police.target.global('vehicle', 'vehicle', {
        {
            label = 'Put Suspect In Vehicle',
            icon = 'car',
            canInteract = function()
                return Police.escortedTarget ~= nil or Police.draggedTarget ~= nil
            end,
            onSelect = function(entity)
                local target = Police.escortedTarget or Police.draggedTarget
                if not target then return end
                local netId = NetworkGetNetworkIdFromEntity(entity)
                TriggerServerEvent('qbpolice:server:putInVehicle', target, netId, -1)
            end,
        },
    })
end
registerVehicleTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerVehicleTargets() end
end)
