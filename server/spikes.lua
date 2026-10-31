-- Spike strips -- raw CreateObject, never Kora.entities (that spawner is
-- explicitly local/non-networked; a deployed strip must be visible to every
-- player on the road, not just the deploying officer). Server-side
-- CreateObject already creates a real networked entity, same precedent as
-- Core.garage.spawnVehicle's server-side CreateVehicle.

Police.spikes = Police.spikes or {}        -- netId -> { entity, officer, coords, deployedAt }
Police.spikesByOfficer = Police.spikesByOfficer or {}  -- officerSrc -> count

---@param officerSrc integer
---@param coords table
---@return integer|false netId
---@return string|nil error
function Police.deploySpike(officerSrc, coords)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if type(coords) ~= 'table' or not Kora.util.isFiniteNumber(coords.x)
        or not Kora.util.isFiniteNumber(coords.y) or not Kora.util.isFiniteNumber(coords.z) then
        return false, 'invalid coords'
    end
    if (Police.spikesByOfficer[officerSrc] or 0) >= Config.spikes.maxDeployed then
        return false, 'too many strips deployed'
    end

    local ped = GetPlayerPed(officerSrc)
    if not ped or ped == 0 then return false, 'no ped' end

    -- Coordinates originate at the client because only it knows the camera's
    -- forward vector. The server still owns where a networked object may be
    -- created: accept the small forward offset used by client/spikes.lua, not
    -- arbitrary world positions or non-finite native arguments.
    local requested = vector3(coords.x, coords.y, coords.z)
    if #(GetEntityCoords(ped) - requested) > Config.spikes.deployDistance then
        return false, 'deployment position is too far away'
    end

    local cleanCoords = { x = coords.x, y = coords.y, z = coords.z }
    local obj = CreateObject(joaat(Config.spikes.model), cleanCoords.x, cleanCoords.y, cleanCoords.z, true, true, false)
    if not obj or obj == 0 then return false, 'failed to create strip' end

    local netId = NetworkGetNetworkIdFromEntity(obj)
    Police.spikes[netId] = { entity = obj, officer = officerSrc, coords = cleanCoords, deployedAt = GetGameTimer() }
    Police.spikesByOfficer[officerSrc] = (Police.spikesByOfficer[officerSrc] or 0) + 1

    TriggerClientEvent('qbpolice:client:spikeDeployed', -1, netId, cleanCoords)
    TriggerClientEvent('police:client:spawnObject', -1, netId, cleanCoords)

    SetTimeout(Config.spikes.lifetime, function() Police.removeSpike(netId) end)
    return netId
end

---@param netId integer
function Police.removeSpike(netId)
    local entry = Police.spikes[netId]
    if not entry then return false end
    Police.spikes[netId] = nil
    Police.spikesByOfficer[entry.officer] = math.max(0, (Police.spikesByOfficer[entry.officer] or 1) - 1)
    if entry.entity and DoesEntityExist(entry.entity) then DeleteEntity(entry.entity) end
    TriggerClientEvent('qbpolice:client:spikeRemoved', -1, netId)
    -- Legacy listeners still get lifecycle parity, but only after this
    -- server-owned registry has actually removed a known strip.
    TriggerClientEvent('police:client:SyncSpikes', -1, netId, false)
    return true
end

RegisterNetEvent('qbpolice:server:deploySpike', function(coords)
    local netId, err = Police.deploySpike(source, coords)
    if not netId then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:removeSpike', function(netId)
    local entry = Police.spikes[tonumber(netId)]
    if entry and entry.officer == source then Police.removeSpike(tonumber(netId)) end
end)

AddEventHandler('playerDropped', function()
    Police.spikesByOfficer[source] = nil
end)
