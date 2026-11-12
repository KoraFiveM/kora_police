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
    local job = exports.kora_core:getJob(src)
    if not job or job.name ~= Config.police.job then return false, Kora.lang('Notify.not_employed') end
    if not nearDutyPoint(src) then return false, Kora.lang('Notify.use_duty_point') end
    onDuty = onDuty == true
    if job.onduty == onDuty then return true end

    local current = GetGameTimer()
    if lastDutyChange[src] and current - lastDutyChange[src] < Config.duty.actionCooldown then
        return false, Kora.lang('Notify.wait_before_duty_change')
    end
    local changed, err = exports.kora_core:setJobDuty(src, onDuty)
    if changed then lastDutyChange[src] = current end
    return changed, err
end

local function toggleDuty(src)
    local job = exports.kora_core:getJob(src)
    local onDuty = job ~= nil and not job.onduty
    local changed, err = setDuty(src, onDuty)
    Kora.notify.send(src, {
        message = changed and (onDuty and Kora.lang('Notify.now_on_duty') or Kora.lang('Notify.now_off_duty'))
            or (err or Kora.lang('Notify.duty_change_failed')),
        type = changed and 'success' or 'error',
    })
    return changed
end

Kora.commands.add('police-duty', 'Toggle police duty at a police station', {}, false, function(source)
    toggleDuty(source)
end)

Kora.events.register('kora_police:server:toggleDuty', function(src)
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
        if not exports.kora_core:getByPlate(plate) then
            exports.kora_core:createVehicle(nil, veh.model, plate, Config.police.job)
        end
    end
end
CreateThread(ensureFleet)

---@param src integer
---@param plate string
---@return integer|false networkId
---@return string|nil error
function Police.spawnDutyVehicle(src, plate)
    if not Police.isPolice(src) then return false, Kora.lang('Notify.on_duty_police') end
    local row = exports.kora_core:getByPlate(plate)
    if not row or row.job ~= Config.police.job then return false, Kora.lang('Notify.not_fleet_vehicle') end
    local index = tonumber(tostring(plate):match('^POLICE(%d+)$'))
    local configured = index and Config.duty.vehicles[index]
    if not configured then return false, Kora.lang('Notify.unknown_fleet_spawn') end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(configured.coords.x, configured.coords.y, configured.coords.z)) > Config.duty.vehicleSpawnDistance then
        return false, Kora.lang('Notify.too_far_from_garage')
    end
    return exports.kora_core:spawnVehicle(src, plate, configured.coords, configured.coords.w or 0.0)
end

---@param src integer
---@param plate string
---@return boolean, string|nil
function Police.storeDutyVehicle(src, plate)
    if not Police.isPolice(src) then return false, Kora.lang('Notify.on_duty_police') end
    local row = exports.kora_core:getByPlate(plate)
    if not row or row.job ~= Config.police.job then return false, Kora.lang('Notify.not_fleet_vehicle') end
    local vehicle = Police.findVehicleByPlate(plate)
    if not vehicle or Police.distanceToEntity(src, vehicle) > Config.cuff.distance + 2.0 then
        return false, Kora.lang('Notify.fleet_vehicle_not_nearby')
    end
    local ok, err = exports.kora_core:storeVehicle(plate, {})
    if not ok then return false, err end
    DeleteEntity(vehicle)
    return true
end

-- `source` is only valid until the handler first yields (the kora_core
-- vehicle exports wait on kora_sql), so it is captured up front.
RegisterNetEvent('kora_police:server:spawnDutyVehicle', function(plate, coords, heading)
    local src = source
    local networkId, err = Police.spawnDutyVehicle(src, plate)
    if not networkId then TriggerClientEvent('QBCore:Notify', src, err, 'error') end
end)
RegisterNetEvent('kora_police:server:storeDutyVehicle', function(plate)
    local src = source
    local ok, err = Police.storeDutyVehicle(src, plate)
    if not ok then TriggerClientEvent('QBCore:Notify', src, err, 'error') end
end)
