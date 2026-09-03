-- Duty toggle (QB.interact -- a lighter primitive than a full qbtarget zone
-- for a simple point of interaction) and the patrol-fleet spawn/store loop.

-- Station blips. Deliberately NOT inside registerDutyZones below: that function
-- re-runs on every qbtarget restart (qbtarget drops its own registrations when
-- it stops, so they have to be re-made), while qblib's blip registry only clears
-- when QBPOLICE stops. Creating them there stacked a second station blip on the
-- map every time qbtarget was restarted.
--
-- Coordinates come from the same Config.duty.points a zone is built from, so a
-- moved station cannot leave a stale blip behind.
local function registerStationBlips()
    for _, point in ipairs(Config.duty.points) do
        if point.blip and point.blip.enabled then
            QB.blips.create(point.coords, point.blip)
        end
    end
end
registerStationBlips()

local function registerDutyZones()
    for _, point in ipairs(Config.duty.points) do
        exports.qbtarget:addSphereZone({
            coords = point.coords,
            radius = point.radius,
            distance = point.radius + 1.0,
            options = {
                {
                    label = point.label,
                    icon = 'badge',
                    canInteract = function()
                        local job = exports.qbcore:getPlayerData({ 'job' })
                        return job ~= nil and job.name == Config.police.job
                    end,
                    onSelect = function()
                        TriggerServerEvent('qbpolice:server:toggleDuty')
                    end,
                },
            },
        })
    end

    for index, veh in ipairs(Config.duty.vehicles) do
        local plate = ('POLICE%02d'):format(index)
        exports.qbtarget:addSphereZone({
            coords = veh.coords,
            radius = 2.0,
            distance = 3.0,
            options = {
                {
                    label = ('Take Out %s'):format(veh.label),
                    icon = 'car',
                    canInteract = function()
                        return Police.isOnDuty()
                    end,
                    onSelect = function()
                        TriggerServerEvent('qbpolice:server:spawnDutyVehicle', plate, veh.coords, veh.coords.w or 0.0)
                    end,
                },
            },
        })
    end

    exports.qbtarget:addGlobalType('vehicle', {
        {
            label = 'Store Patrol Vehicle',
            icon = 'car',
            canInteract = function(entity)
                return Police.isOnDuty() and GetPedInVehicleSeat(entity, -1) == QB.cache.ped()
            end,
            onSelect = function(entity)
                local plate = GetVehicleNumberPlateText(entity)
                TriggerServerEvent('qbpolice:server:storeDutyVehicle', plate)
                DeleteEntity(entity)
            end,
        },
    })
end
registerDutyZones()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qbtarget' then registerDutyZones() end
end)
