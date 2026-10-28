-- GPS tracker (ankle bracelet) -- an officer attaches one to a target;
-- on-duty officers then receive that target's position pushes periodically.

---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.setTracker(officerSrc, targetSrc, active)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if not exports.kora_core:getPlayerData(targetSrc) then return false, 'target not found' end
    if active == false then
        Police.tracked[targetSrc] = nil
    else
        if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end
        Police.tracked[targetSrc] = true
    end
    return true
end

---@return integer[] tracked src list currently active
function Police.getTracked()
    local out = {}
    for src in pairs(Police.tracked) do out[#out + 1] = src end
    return out
end

RegisterNetEvent('qbpolice:server:setTracker', function(target, active)
    local ok, err = Police.setTracker(source, tonumber(target), active ~= false)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)

RegisterNetEvent('qbpolice:server:sendTrackerLocation', function()
    local src = source
    if not Police.tracked[src] then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)
    for _, officer in ipairs(exports.kora_core:getPlayersByJob(Config.police.job, true)) do
        TriggerClientEvent('qbpolice:client:trackerLocation', officer, src, coords)
        TriggerClientEvent('police:client:SendTrackerLocation', officer, src, coords)
    end
end)

CreateThread(function()
    while true do
        Wait(15000)
        for src in pairs(Police.tracked) do TriggerClientEvent('qbpolice:client:requestTrackerPing', src) end
    end
end)
