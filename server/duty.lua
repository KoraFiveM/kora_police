-- Duty toggle and the patrol-fleet register/spawn/store loop, all on
-- Core.garage (job-fleet rows: citizenid is nil, job = Config.police.job).

local lastDutyChange = {}

local function nearDutyPoint(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    for _, point in ipairs(Config.duty.points) do
        local radius = (tonumber(point.radius) or 1.5) + 1.0
        if #(coords - vector3(point.coords.x, point.coords.y, point.coords.z)) <= radius then return true end
    end
    return false
end

local function setDuty(src, onDuty)
    local job = exports.qbcore:getJob(src)
    if not job or job.name ~= Config.police.job then return false, 'You are not employed by this police service.' end
    if not nearDutyPoint(src) then return false, 'Use a police duty point to change duty status.' end
    onDuty = onDuty == true
    if job.onduty == onDuty then return true end

    local current = GetGameTimer()
    if lastDutyChange[src] and current - lastDutyChange[src] < Config.duty.actionCooldown then
        return false, 'Wait before changing duty status again.'
    end
    local changed, err = exports.qbcore:setJobDuty(src, onDuty)
    if changed then lastDutyChange[src] = current end
    return changed, err
end

local function toggleDuty(src)
    local job = exports.qbcore:getJob(src)
    local onDuty = job ~= nil and not job.onduty
    local changed, err = setDuty(src, onDuty)
    QB.notify.send(src, {
        message = changed and (onDuty and 'You are now on duty.' or 'You are now off duty.')
            or (err or 'Duty status could not be changed.'),
        type = changed and 'success' or 'error',
    })
    return changed
end

QB.commands.add('police-duty', 'Toggle police duty at a police station', {}, false, function(source)
    toggleDuty(source)
end)

QB.events.register('qbpolice:server:toggleDuty', function(src)
    toggleDuty(src)
end, { rateLimit = { max = 2, window = 3000 } })

AddEventHandler('playerDropped', function()
    lastDutyChange[source] = nil
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
