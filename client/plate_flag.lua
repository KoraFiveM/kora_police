-- Flag/unflag a plate, and a lightweight ALPR-style poll: while on duty in a
-- vehicle, nearby plates are checked against the flag list and trigger
-- `FlaggedPlateTriggered` for every on-duty officer (server-side dedupe of
-- who gets notified; this client only decides when to ask).

exports.qbtarget:addGlobalType('vehicle', {
    options = {
        {
            label = 'Flag Plate',
            icon = 'flag',
            canInteract = function()
                return Police.isOnDuty()
            end,
            onSelect = function(entity)
                local plate = GetVehicleNumberPlateText(entity)
                local result = QB.nui.openInputDialog(
                    { { id = 'reason', label = 'Reason', type = 'text', default = 'BOLO' } },
                    ('Flag %s'):format(plate)
                )
                if not result or not result.values then return end
                TriggerServerEvent('qbpolice:server:flagPlate', plate, result.values.reason)
            end,
        },
        {
            label = 'Unflag Plate',
            icon = 'flag-off',
            canInteract = function()
                return Police.isOnDuty()
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:unflagPlate', GetVehicleNumberPlateText(entity))
            end,
        },
    },
})

local checked = {}
local lastReset = GetGameTimer()

CreateThread(function()
    while true do
        Wait(3000)
        if GetGameTimer() - lastReset > 60000 then checked = {}; lastReset = GetGameTimer() end
        if Police.isOnDuty() then
            local vehicle = QB.cache.vehicle()
            if vehicle and QB.cache.seat() == -1 then
                local coords = GetEntityCoords(vehicle)
                local nearby = GetGamePool('CVehicle')
                for _, other in ipairs(nearby) do
                    if other ~= vehicle and #(GetEntityCoords(other) - coords) <= 20.0 then
                        local plate = GetVehicleNumberPlateText(other)
                        if not checked[plate] then
                            checked[plate] = true
                            TriggerServerEvent('qbpolice:server:plateSpotted', plate)
                        end
                    end
                end
            end
        else
            Wait(5000)
        end
    end
end)

RegisterNetEvent('qbpolice:client:flaggedPlateTriggered', function(plate, reason)
    Police.notify(('Flagged plate spotted: %s (%s)'):format(plate, reason), 'warning')
end)
RegisterNetEvent('police:client:FlaggedPlateTriggered', function(plate, reason)
    Police.notify(('Flagged plate spotted: %s (%s)'):format(plate, reason), 'warning')
end)
