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
local scanRunning = false

local function canScan()
    return Police.isOnDuty() and QB.cache.vehicle() and QB.cache.seat() == -1
end

local function startScan()
    if scanRunning or not canScan() then return end
    scanRunning = true

    CreateThread(function()
        local scans, vehicles = 0, 0
        while canScan() do
            Wait(3000)
            if not canScan() then break end

            local vehicle = QB.cache.vehicle()
            local coords = GetEntityCoords(vehicle)
            local maxDistanceSq = 20.0 * 20.0
            if Config.performance.diagnostics then scans = scans + 1 end

            if GetGameTimer() - lastReset > 60000 then
                checked = {}
                lastReset = GetGameTimer()
            end

            for _, other in ipairs(GetGamePool('CVehicle')) do
                if other ~= vehicle then
                    if Config.performance.diagnostics then vehicles = vehicles + 1 end
                    local otherCoords = GetEntityCoords(other)
                    local dx = otherCoords.x - coords.x
                    local dy = otherCoords.y - coords.y
                    local dz = otherCoords.z - coords.z
                    if dx * dx + dy * dy + dz * dz <= maxDistanceSq then
                        local plate = GetVehicleNumberPlateText(other)
                        if not checked[plate] then
                            checked[plate] = true
                            TriggerServerEvent('qbpolice:server:plateSpotted', plate)
                        end
                    end
                end
            end
        end

        scanRunning = false
        if Config.performance.diagnostics then
            print(('[qbpolice] ALPR scanner stopped after %d scans / %d vehicle checks'):format(scans, vehicles))
        end
    end)
end

QB.cache.onChange('vehicle', function(vehicle)
    if vehicle then startScan() end
end)
QB.cache.onChange('seat', function(seat)
    if seat == -1 then startScan() end
end)

-- The replicated player-data mirror is push-driven. A duty transition can
-- make an already-seated driver eligible without a vehicle cache change.
exports.qbcore:onPlayerDataChange({ 'job' }, startScan)

CreateThread(function()
    Wait(0)
    startScan()
end)

RegisterNetEvent('qbpolice:client:flaggedPlateTriggered', function(plate, reason)
    Police.notify(('Flagged plate spotted: %s (%s)'):format(plate, reason), 'warning')
end)
RegisterNetEvent('police:client:FlaggedPlateTriggered', function(plate, reason)
    Police.notify(('Flagged plate spotted: %s (%s)'):format(plate, reason), 'warning')
end)
