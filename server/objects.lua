-- Stock `police:server:spawnObject(type)` / `deleteObject(objectId)` road props
-- (cones, barriers, signs, tents, lights) and `heli:server:spotlight`. Stock lets
-- the client create the networked prop and lets any client delete any prop; here
-- the server creates and removes them (same precedent as spike strips), for an
-- on-duty officer, at their own position, within a per-officer cap.

Police.objects = Police.objects or {}                 -- id -> { entity, netId, officer, type, coords, createdAt }
Police.objectsByOfficer = Police.objectsByOfficer or {}
local nextObjectId = 10000
local lastPlacedAt = {}

---@param id integer
---@return boolean
function Police.removeObject(id)
    local entry = Police.objects[id]
    if not entry then return false end
    Police.objects[id] = nil
    Police.objectsByOfficer[entry.officer] = math.max(0, (Police.objectsByOfficer[entry.officer] or 1) - 1)
    if entry.entity and DoesEntityExist(entry.entity) then DeleteEntity(entry.entity) end
    TriggerClientEvent('police:client:removeObject', -1, id)
    return true
end

---@param officerSrc integer
---@param objectType string key of Config.objects.types
---@return integer|false id
---@return string|nil error
function Police.spawnObject(officerSrc, objectType)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    local definition = type(objectType) == 'string' and Config.objects.types[objectType]
    if not definition then return false, 'unknown object type' end
    local now = GetGameTimer()
    if lastPlacedAt[officerSrc] and now - lastPlacedAt[officerSrc] < Config.objects.cooldown then return false, 'too fast' end
    if (Police.objectsByOfficer[officerSrc] or 0) >= Config.objects.maxPerOfficer then return false, 'too many objects placed' end
    local ped = GetPlayerPed(officerSrc)
    if not ped or ped == 0 then return false, 'no ped' end
    lastPlacedAt[officerSrc] = now

    local position, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local radians = math.rad(heading)
    local coords = {
        x = position.x - math.sin(radians) * Config.objects.placeDistance,
        y = position.y + math.cos(radians) * Config.objects.placeDistance,
        z = position.z - 0.9,
    }
    local entity = CreateObject(joaat(definition.model), coords.x, coords.y, coords.z, true, true, false)
    if not entity or entity == 0 then return false, 'failed to create object' end
    SetEntityHeading(entity, heading)
    if definition.freeze then FreezeEntityPosition(entity, true) end

    local id = nextObjectId
    nextObjectId = nextObjectId + 1
    local netId = NetworkGetNetworkIdFromEntity(entity)
    Police.objects[id] = { entity = entity, netId = netId, officer = officerSrc, type = objectType, coords = coords, createdAt = now }
    Police.objectsByOfficer[officerSrc] = (Police.objectsByOfficer[officerSrc] or 0) + 1

    TriggerClientEvent('police:client:spawnObject', officerSrc, id, objectType, officerSrc)
    TriggerClientEvent('qbpolice:client:objectPlaced', officerSrc, id, netId, heading)
    SetTimeout(Config.objects.lifetime, function() Police.removeObject(id) end)
    return id
end

---@param officerSrc integer
---@param objectId any
---@return boolean, string|nil
function Police.deleteObject(officerSrc, objectId)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    objectId = tonumber(objectId)
    local entry = objectId and Police.objects[objectId]
    if not entry then return false, 'unknown object' end
    local ped = GetPlayerPed(officerSrc)
    if not ped or ped == 0 then return false, 'no ped' end
    local at = vector3(entry.coords.x, entry.coords.y, entry.coords.z)
    if #(GetEntityCoords(ped) - at) > Config.objects.deleteDistance then return false, 'too far away' end
    return Police.removeObject(objectId)
end

---@param officerSrc integer
---@return boolean, string|nil
function Police.deleteNearestObject(officerSrc)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    local ped = GetPlayerPed(officerSrc)
    if not ped or ped == 0 then return false, 'no ped' end
    local origin = GetEntityCoords(ped)
    local bestId, bestDistance
    for id, entry in pairs(Police.objects) do
        local distance = #(origin - vector3(entry.coords.x, entry.coords.y, entry.coords.z))
        if distance <= Config.objects.deleteDistance and (not bestDistance or distance < bestDistance) then
            bestId, bestDistance = id, distance
        end
    end
    if not bestId then return false, 'no object nearby' end
    return Police.removeObject(bestId)
end

RegisterNetEvent('qbpolice:server:deleteNearestObject', function()
    local ok, err = Police.deleteNearestObject(source)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, entry in pairs(Police.objects) do
        if entry.entity and DoesEntityExist(entry.entity) then DeleteEntity(entry.entity) end
    end
end)

AddEventHandler('playerDropped', function()
    lastPlacedAt[source] = nil
end)

local lastSpotlightAt = {}

---Stock `heli:server:spotlight(state)` rebroadcasts to every client. Here only
---an on-duty officer seated in the front of a helicopter may toggle it, and the
---state must be a boolean.
---@param src integer
---@param state any
---@return boolean
function Police.setHeliSpotlight(src, state)
    if type(state) ~= 'boolean' or not Police.isLeo(src) then return false end
    local now = GetGameTimer()
    if lastSpotlightAt[src] and now - lastSpotlightAt[src] < Config.heli.spotlightCooldown then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 or GetVehicleType(vehicle) ~= 'heli' then return false end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped and GetPedInVehicleSeat(vehicle, 0) ~= ped then return false end
    lastSpotlightAt[src] = now
    TriggerClientEvent('heli:client:spotlight', -1, src, state)
    return true
end
AddEventHandler('playerDropped', function() lastSpotlightAt[source] = nil end)
