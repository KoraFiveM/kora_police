-- Restrain/release. `soft` cuffs (via the `handcuffs` useable item, usable by
-- anyone) can be escaped with the ported qbx_police-style WASD skillcheck;
-- `hard` cuffs (via an on-duty officer's own action) cannot -- only an
-- officer or an /unjail-equivalent release clears those.

-- src -> { soft = boolean, officer = integer|nil, attemptsUsed = integer, cooldownUntil = integer }
Police.cuffState = Police.cuffState or {}

---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.cuff(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if officerSrc == targetSrc then return false, 'cannot cuff yourself' end
    if not exports.qbcore:getPlayerData(targetSrc) then return false, 'target not found' end
    if Police.isCuffed(targetSrc) then return false, 'already cuffed' end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end

    exports.qbcore:setMetaData(targetSrc, 'ishandcuffed', true)
    Police.cuffState[targetSrc] = { soft = false, officer = officerSrc, attemptsUsed = 0, cooldownUntil = 0 }
    TriggerClientEvent('qbpolice:client:cuffed', targetSrc, true, false)
    TriggerClientEvent('qbpolice:client:cuffed', officerSrc, true, false, targetSrc)
    return true
end

---@param requesterSrc integer Officer, or the cuffed player releasing themself after a successful escape.
---@param targetSrc integer
---@return boolean, string|nil
function Police.uncuff(requesterSrc, targetSrc)
    if not Police.isCuffed(targetSrc) then return false, 'not cuffed' end
    local state = Police.cuffState[targetSrc]
    local isOfficer = Police.isPolice(requesterSrc)
    if requesterSrc ~= targetSrc and not isOfficer then return false, 'not authorised' end
    if requesterSrc == targetSrc and not (state and state.soft) then return false, 'cannot self-release a hard cuff' end
    if isOfficer and Police.distanceBetween(requesterSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end

    exports.qbcore:setMetaData(targetSrc, 'ishandcuffed', false)
    Police.cuffState[targetSrc] = nil
    TriggerClientEvent('qbpolice:client:cuffed', targetSrc, false)
    if requesterSrc ~= targetSrc then TriggerClientEvent('qbpolice:client:cuffed', requesterSrc, false, false, targetSrc) end
    return true
end

---Soft-cuff via the `handcuffs` useable item -- usable by anyone, not just
---police. Resolves the target as the single other online player within
---Config.cuff.distance (item use carries no client-picked target).
---@param src integer
---@return boolean, string|nil
function Police.softCuffNearby(src)
    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return false, 'no ped' end
    local srcCoords = GetEntityCoords(srcPed)

    local candidates = {}
    for _, other in ipairs(exports.qbcore:getPlayers()) do
        if other ~= src then
            local ped = GetPlayerPed(other)
            if ped and ped ~= 0 and #(GetEntityCoords(ped) - srcCoords) <= Config.cuff.distance and not Police.isCuffed(other) then
                candidates[#candidates + 1] = other
            end
        end
    end

    if #candidates == 0 then return false, 'no one nearby to cuff' end
    if #candidates > 1 then return false, 'too many people nearby -- move closer to just one target' end

    local target = candidates[1]
    exports.qbcore:setMetaData(target, 'ishandcuffed', true)
    Police.cuffState[target] = { soft = true, officer = nil, attemptsUsed = 0, cooldownUntil = 0 }
    TriggerClientEvent('qbpolice:client:cuffed', target, true, true)
    TriggerClientEvent('qbpolice:client:cuffed', src, true, true, target)
    return true
end

exports.qbcore:createUseable('handcuffs', function(src)
    local ok, err = Police.softCuffNearby(src)
    if not ok then TriggerClientEvent('QBCore:Notify', src, err, 'error') end
    return ok
end)

---A soft-cuffed suspect's client won the QB.minigames escape skillcheck --
---revalidate server-side (still soft-cuffed, attempts/cooldown) before
---actually releasing.
---@param src integer
---@return boolean, string|nil
function Police.breakCuffs(src)
    local state = Police.cuffState[src]
    if not state or not state.soft then return false, 'not soft-cuffed' end
    if GetGameTimer() < state.cooldownUntil then return false, 'on cooldown' end
    if state.attemptsUsed >= Config.cuff.breakCuffsAttempts then return false, 'no attempts remaining' end

    state.attemptsUsed = state.attemptsUsed + 1
    return Police.uncuff(src, src)
end

---Records a failed escape attempt (client-reported); applies the cooldown.
---@param src integer
function Police.breakCuffsFailed(src)
    local state = Police.cuffState[src]
    if not state or not state.soft then return end
    state.attemptsUsed = state.attemptsUsed + 1
    state.cooldownUntil = GetGameTimer() + Config.cuff.breakCuffsCooldown
end

RegisterNetEvent('qbpolice:server:cuff', function(target)
    local ok, err = Police.cuff(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:uncuff', function(target)
    local ok, err = Police.uncuff(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:breakCuffsResult', function(success)
    if success then
        Police.breakCuffs(source)
    else
        Police.breakCuffsFailed(source)
    end
end)

QB.callback.register('qbpolice:server:getCuffed', function(src, target)
    return Police.isCuffed(target or src)
end)
