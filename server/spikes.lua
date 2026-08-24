-- Spike strips -- raw CreateObject, never QB.entities (that spawner is
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
    if type(coords) ~= 'table' or not coords.x then return false, 'invalid coords' end
    if (Police.spikesByOfficer[officerSrc] or 0) >= Config.spikes.maxDeployed then
        return false, 'too many strips deployed'
    end

    local obj = CreateObject(GetHashKey(Config.spikes.model), coords.x, coords.y, coords.z, true, true, false)
    if not obj or obj == 0 then return false, 'failed to create strip' end
    PlaceObjectOnGroundProperly(obj)

    local netId = NetworkGetNetworkIdFromEntity(obj)
    Police.spikes[netId] = { entity = obj, officer = officerSrc, coords = coords, deployedAt = GetGameTimer() }
    Police.spikesByOfficer[officerSrc] = (Police.spikesByOfficer[officerSrc] or 0) + 1

    TriggerClientEvent('qbpolice:client:spikeDeployed', -1, netId, coords)
    TriggerClientEvent('police:client:spawnObject', -1, netId, coords)

    SetTimeout(Config.spikes.lifetime, function() Police.removeSpike(netId) end)
    return netId
end

---@param netId integer
function Police.removeSpike(netId)
    local entry = Police.spikes[netId]
    if not entry then return end
    Police.spikes[netId] = nil
    Police.spikesByOfficer[entry.officer] = math.max(0, (Police.spikesByOfficer[entry.officer] or 1) - 1)
    if entry.entity and DoesEntityExist(entry.entity) then DeleteEntity(entry.entity) end
    TriggerClientEvent('qbpolice:client:spikeRemoved', -1, netId)
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
