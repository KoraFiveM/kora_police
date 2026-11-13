-- GPS tracker (ankle bracelet) -- an officer attaches one to a target;
-- on-duty officers then receive that target's position pushes periodically.

---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.setTracker(officerSrc, targetSrc, active)
    if not Police.isPolice(officerSrc) then return false, Kora.lang('Notify.on_duty_police') end
    if not exports.kora_core:getPlayerData(targetSrc) then return false, Kora.lang('Notify.player_not_found') end
    if active == false then
        Police.tracked[targetSrc] = nil
    else
        if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, Kora.lang('Notify.too_far_away') end
        Police.tracked[targetSrc] = true
    end
    exports.kora_core:setMetaData(targetSrc, 'tracker', active ~= false)
    return true
end

local function fullName(src)
    local charinfo = exports.kora_core:getPlayerData(src, { 'charinfo' }) or {}
    return ('%s %s'):format(charinfo.firstname or '', charinfo.lastname or '')
end

local function isTracked(src)
    return Police.tracked[src] == true or exports.kora_core:getMetaData(src, 'tracker') == true
end

---Stock `police:server:SetTracker(target)` toggles the anklet. Unlike stock, the
---officer must be on duty and in reach for both directions, and nobody is kicked.
---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil, boolean|nil active
function Police.toggleTracker(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, Kora.lang('Notify.on_duty_police') end
    if type(targetSrc) ~= 'number' or targetSrc == officerSrc then return false, Kora.lang('Notify.player_not_found') end
    if not exports.kora_core:getPlayerData(targetSrc) then return false, Kora.lang('Notify.player_not_found') end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, Kora.lang('Notify.too_far_away') end
    local active = not isTracked(targetSrc)
    Police.tracked[targetSrc] = active or nil
    exports.kora_core:setMetaData(targetSrc, 'tracker', active)
    local name = fullName(targetSrc)
    if active then
        TriggerClientEvent('QBCore:Notify', targetSrc, 'You put on an ankle tracker.', 'success')
        TriggerClientEvent('QBCore:Notify', officerSrc, ('You put on an ankle tracker on %s'):format(name), 'success')
    else
        TriggerClientEvent('QBCore:Notify', targetSrc, 'Your ankle tracker is taken off.', 'success')
        TriggerClientEvent('QBCore:Notify', officerSrc, ('You took off %s tracker'):format(name), 'success')
    end
    TriggerClientEvent('police:client:SetTracker', targetSrc, active)
    return true, nil, active
end

local lastLocationReplyAt = {}

---Stock `police:server:SendTrackerLocation(coords, requestId)`: a tracked player
---answers an officer's location request. The coordinates are read from the
---caller's ped (the client-supplied ones are ignored), the requester must be an
---on-duty officer, and replies are rate limited per player.
---@param src integer
---@param requestId any
---@return boolean
function Police.replyTrackerLocation(src, requestId)
    requestId = tonumber(requestId)
    if not requestId or not isTracked(src) or not Police.isPolice(requestId) then return false end
    local now = GetGameTimer()
    if lastLocationReplyAt[src] and now - lastLocationReplyAt[src] < Config.tracker.locationCooldown then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    lastLocationReplyAt[src] = now
    local position = GetEntityCoords(ped)
    local coords = { x = position.x, y = position.y, z = position.z }
    local message = ('The location of %s is marked on your map'):format(fullName(src))
    TriggerClientEvent('police:client:TrackerMessage', requestId, message, coords)
    TriggerClientEvent('qb-phone:client:addPoliceAlert', requestId, { title = 'Anklet location', coords = coords, description = message })
    return true
end
AddEventHandler('playerDropped', function() lastLocationReplyAt[source] = nil end)

---@return integer[] tracked src list currently active
function Police.getTracked()
    local out = {}
    for src in pairs(Police.tracked) do out[#out + 1] = src end
    return out
end

RegisterNetEvent('kora_police:server:setTracker', function(target, active)
    local ok, err = Police.setTracker(source, tonumber(target), active ~= false)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)

RegisterNetEvent('kora_police:server:sendTrackerLocation', function()
    local src = source
    if not Police.tracked[src] then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)
    for _, officer in ipairs(exports.kora_core:getPlayersByJob(Config.police.job, true)) do
        TriggerClientEvent('kora_police:client:trackerLocation', officer, src, coords)
        TriggerClientEvent('police:client:SendTrackerLocation', officer, src, coords)
    end
end)

CreateThread(function()
    while true do
        Wait(15000)
        for src in pairs(Police.tracked) do TriggerClientEvent('kora_police:client:requestTrackerPing', src) end
    end
end)
