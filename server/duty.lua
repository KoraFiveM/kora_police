-- Duty toggle and the patrol-fleet register/spawn/store loop, all on
-- Core.garage (job-fleet rows: citizenid is nil, job = Config.police.job).

-- Duty is normally toggled at a station target zone, which is fine in play but
-- makes the whole resource awkward to exercise -- you cannot go on duty without
-- travelling to a specific spot. This is the same toggle as a chat command,
-- mirroring qbambulance's own /ems-duty.
QB.commands.add('police-duty', 'Toggle police duty', {}, false, function(source)
    local job = exports.qbcore:getJob(source)
    if not job or job.type ~= Config.police.jobType then
        return QB.notify.send(source, { message = 'You are not employed in law enforcement.', type = 'error' })
    end

    local onDuty = not job.onduty
    exports.qbcore:setJobDuty(source, onDuty)
    QB.notify.send(source, {
        message = onDuty and 'You are now on duty.' or 'You are now off duty.',
        type = 'success',
    })
end)

RegisterNetEvent('qbpolice:server:toggleDuty', function()
    local src = source
    local job = Police.job(src)
    if not job or job.name ~= Config.police.job then return end
    exports.qbcore:setJobDuty(src, not job.onduty)
end)

---Ensures every configured duty vehicle has a `player_vehicles` row (job
---fleet, citizenid unset). Idempotent -- createVehicle rejects a duplicate
---plate, which is exactly the "already registered" case on every subsequent
---boot.
local function ensureFleet()
    for index, veh in ipairs(Config.duty.vehicles) do
        local plate = ('POLICE%02d'):format(index)
        if not exports.qbcore:getByPlate(plate) then
            exports.qbcore:createVehicle(nil, veh.model, plate, Config.police.job)
        end
    end
end
CreateThread(ensureFleet)

---@param src integer
---@param plate string
---@param coords table
---@param heading number
---@return integer|false networkId
---@return string|nil error
function Police.spawnDutyVehicle(src, plate)
    if not Police.isPolice(src) then return false, 'not an on-duty officer' end
    local row = exports.qbcore:getByPlate(plate)
    if not row or row.job ~= Config.police.job then return false, 'not a fleet vehicle' end
    local index = tonumber(tostring(plate):match('^POLICE(%d+)$'))
    local configured = index and Config.duty.vehicles[index]
    if not configured then return false, 'unknown fleet spawn' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(configured.coords.x, configured.coords.y, configured.coords.z)) > Config.duty.vehicleSpawnDistance then
        return false, 'too far from the fleet garage'
    end
    return exports.qbcore:spawnVehicle(src, plate, configured.coords, configured.coords.w or 0.0)
end

---@param src integer
---@param plate string
---@return boolean, string|nil
function Police.storeDutyVehicle(src, plate)
    if not Police.isPolice(src) then return false, 'not an on-duty officer' end
    local row = exports.qbcore:getByPlate(plate)
    if not row or row.job ~= Config.police.job then return false, 'not a fleet vehicle' end
    local vehicle = Police.findVehicleByPlate(plate)
    if not vehicle or Police.distanceToEntity(src, vehicle) > Config.cuff.distance + 2.0 then
        return false, 'fleet vehicle is not nearby'
    end
    local ok, err = exports.qbcore:storeVehicle(plate, {})
    if not ok then return false, err end
    DeleteEntity(vehicle)
    return true
end

RegisterNetEvent('qbpolice:server:spawnDutyVehicle', function(plate, coords, heading)
    local networkId, err = Police.spawnDutyVehicle(source, plate)
    if not networkId then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:storeDutyVehicle', function(plate)
    local ok, err = Police.storeDutyVehicle(source, plate)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
