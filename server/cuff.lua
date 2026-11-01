-- Restrain/release. `soft` cuffs (via the `handcuffs` useable item, usable by
-- anyone) can be escaped with the ported qbx_police-style WASD skillcheck;
-- `hard` cuffs (via an on-duty officer's own action) cannot -- only an
-- officer or an /unjail-equivalent release clears those.

-- src -> { soft = boolean, officer = integer|nil, attemptsUsed = integer, cooldownUntil = integer }
Police.cuffState = Police.cuffState or {}

-- Player-facing wording for a refused cuff/uncuff, so a refusal is never silent.
local REFUSALS = {
    ['not an on-duty officer'] = 'You must be an on-duty police officer to do that.',
    ['cannot cuff yourself'] = 'You cannot cuff yourself.',
    ['target not found'] = 'That player could not be found.',
    ['already cuffed'] = 'They are already cuffed.',
    ['too far away'] = 'You are too far away.',
    ['not cuffed'] = 'They are not cuffed.',
    ['not authorised'] = 'You are not allowed to do that.',
    ['handcuffs required'] = 'You need handcuffs.',
}
---@param err string|nil
---@return string
function Police.cuffRefusal(err)
    return REFUSALS[err] or err or 'That did not work.'
end

---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.cuff(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if officerSrc == targetSrc then return false, 'cannot cuff yourself' end
    if not exports.kora_core:getPlayerData(targetSrc) then return false, 'target not found' end
    if Police.isCuffed(targetSrc) then return false, 'already cuffed' end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end

    exports.kora_core:setMetaData(targetSrc, 'ishandcuffed', true)
    Police.cuffState[targetSrc] = { soft = false, officer = officerSrc, attemptsUsed = 0, cooldownUntil = 0 }
    TriggerClientEvent('qbpolice:client:cuffed', targetSrc, true, false)
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

    exports.kora_core:setMetaData(targetSrc, 'ishandcuffed', false)
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
    if not exports.kora_core:hasItem(src, 'handcuffs') then return false, 'handcuffs required' end
    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return false, 'no ped' end

    local candidates = {}
    for _, other in ipairs(exports.kora_core:getPlayers()) do
        if other ~= src and Police.distanceBetween(src, other) <= Config.cuff.distance and not Police.isCuffed(other) then
            candidates[#candidates + 1] = other
        end
    end

    if #candidates == 0 then return false, 'no one nearby to cuff' end
    if #candidates > 1 then return false, 'too many people nearby -- move closer to just one target' end

    local target = candidates[1]
    exports.kora_core:setMetaData(target, 'ishandcuffed', true)
    Police.cuffState[target] = { soft = true, officer = nil, attemptsUsed = 0, cooldownUntil = 0 }
    TriggerClientEvent('qbpolice:client:cuffed', target, true, true)
    return true
end

exports.kora_core:createUseable('handcuffs', function(src)
    local ok, err = Police.softCuffNearby(src)
    if not ok then Police.notify(src, Police.cuffRefusal(err)) end
    return ok
end)

---A soft-cuffed suspect's client won the Kora.minigames escape skillcheck --
---revalidate both the cuff state and kora_lib's one-use server-issued proof
---before actually releasing.
---@param src integer
---@param proof string
---@return boolean, string|nil
function Police.breakCuffs(src, proof)
    local state = Police.cuffState[src]
    if not state or not state.soft then return false, 'not soft-cuffed' end
    if GetGameTimer() < state.cooldownUntil then return false, 'on cooldown' end
    if state.attemptsUsed >= Config.cuff.breakCuffsAttempts then return false, 'no attempts remaining' end
    local authorization = state.breakAuthorization
    state.breakAuthorization = nil
    if not authorization or not Kora.minigames.consumeProof(src, proof,
        Config.minigames.breakCuffs.type, authorization) then
        return false, 'invalid minigame proof'
    end

    state.attemptsUsed = state.attemptsUsed + 1
    return Police.uncuff(src, src)
end

---Records a failed escape attempt (client-reported); applies the cooldown.
---@param src integer
function Police.breakCuffsFailed(src)
    local state = Police.cuffState[src]
    if not state or not state.soft then return end
    state.breakAuthorization = nil
    state.attemptsUsed = state.attemptsUsed + 1
    state.cooldownUntil = GetGameTimer() + Config.cuff.breakCuffsCooldown
end

---@param src integer
---@return string|nil authorization
---@return string|nil reason
function Police.beginBreakCuffs(src)
    local state = Police.cuffState[src]
    if not state or not state.soft then return nil, 'not soft-cuffed' end
    if state.breakAuthorization then return nil, 'attempt already in progress' end
    if GetGameTimer() < state.cooldownUntil then return nil, 'on cooldown' end
    if state.attemptsUsed >= Config.cuff.breakCuffsAttempts then return nil, 'no attempts remaining' end

    local attempt = state.attemptsUsed + 1
    local difficulty = Config.cuff.breakCuffsDifficulty[math.min(attempt, #Config.cuff.breakCuffsDifficulty)]
    local opts = Config.minigames.breakCuffs.opts[difficulty] or Config.minigames.breakCuffs.opts.medium
    local authorization = Kora.minigames.authorizeProof(src, Config.minigames.breakCuffs.type, opts)
    if not authorization then return nil, 'could not authorize escape attempt' end
    state.breakAuthorization = authorization
    return authorization
end

RegisterNetEvent('qbpolice:server:cuff', function(target)
    local ok, err = Police.cuff(source, tonumber(target))
    if not ok then Police.notify(source, Police.cuffRefusal(err)) end
end)
RegisterNetEvent('qbpolice:server:uncuff', function(target)
    local ok, err = Police.uncuff(source, tonumber(target))
    if not ok then Police.notify(source, Police.cuffRefusal(err)) end
end)
RegisterNetEvent('qbpolice:server:breakCuffsResult', function(proof)
    local escaped = type(proof) == 'string' and Police.breakCuffs(source, proof)
    if escaped then
        Police.notify(source, 'You broke free!', 'success')
    else
        Police.breakCuffsFailed(source)
    end
end)

Kora.callback.register('qbpolice:server:beginBreakCuffs', function(src)
    return Police.beginBreakCuffs(src)
end)

Kora.callback.register('qbpolice:server:getCuffed', function(src, target)
    return Police.isCuffed(target or src)
end)
