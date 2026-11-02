-- Restrain/release. `soft` cuffs (via the `handcuffs` useable item, usable by
-- anyone) can be escaped with the ported qbx_police-style WASD skillcheck;
-- `hard` cuffs (via an on-duty officer's own action) cannot -- only an
-- officer or an /unjail-equivalent release clears those.

-- src -> { soft = boolean, officer = integer|nil, cuffer = integer|nil, attemptsUsed = integer, cooldownUntil = integer }
Police.cuffState = Police.cuffState or {}

-- The restraint is stored once (kora_core metadata `ishandcuffed`, which is what
-- Police.isCuffed reads and what persists) and mirrored to the replicated player
-- state bags below by `restrain`/`release`, the only writers. Clients, the emote
-- menu and kora_inventory only ever read the bags; a client write is reverted.
local STATE_KEY, SOFT_KEY = 'koraCuffed', 'koraCuffedSoft'

-- Player-facing wording for a refused cuff/uncuff, so a refusal is never silent.
local REFUSALS = {
    ['not an on-duty officer'] = 'You must be an on-duty police officer to do that.',
    ['cannot cuff yourself'] = 'You cannot cuff yourself.',
    ['target not found'] = 'That player could not be found.',
    ['already cuffed'] = 'They are already cuffed.',
    ['refreshed'] = 'They were already cuffed -- the restraints were re-applied.',
    ['too far away'] = 'You are too far away.',
    ['not cuffed'] = 'They are not cuffed.',
    ['not authorised'] = 'You are not allowed to do that.',
    ['you are restrained'] = 'You cannot do that while restrained.',
    ['handcuffs required'] = 'You need handcuffs.',
}
---@param err string|nil
---@return string
function Police.cuffRefusal(err)
    return REFUSALS[err] or err or 'That did not work.'
end

---@param src integer
---@param cuffed boolean
---@param soft boolean
local function publish(src, cuffed, soft)
    local player = Player(src)
    local bag = player and player.state
    if not bag then return end
    bag:set(SOFT_KEY, cuffed and soft or false, true)
    bag:set(STATE_KEY, cuffed, true)
end

---Puts the restraint on `targetSrc`, or re-applies it when they are already cuffed
---(the state is written and replicated again, so a client that lost the cuff
---animation gets it back). A hard cuff is never downgraded by a soft one; an
---officer's cuff upgrades a soft one.
---@param targetSrc integer
---@param soft boolean
---@param cuffer integer|nil Who applied it.
---@return table state
local function restrain(targetSrc, soft, cuffer)
    local state = Police.cuffState[targetSrc]
    if state then
        state.soft = state.soft and soft
        state.breakAuthorization = nil
    else
        state = { soft = soft, cuffer = cuffer, attemptsUsed = 0, cooldownUntil = 0 }
        Police.cuffState[targetSrc] = state
    end
    if not soft then state.officer = cuffer or state.officer end
    exports.kora_core:setMetaData(targetSrc, 'ishandcuffed', true)
    publish(targetSrc, true, state.soft)
    TriggerClientEvent('qbpolice:client:cuffed', targetSrc, true, state.soft)
    return state
end

---@param targetSrc integer
local function release(targetSrc)
    exports.kora_core:setMetaData(targetSrc, 'ishandcuffed', false)
    Police.cuffState[targetSrc] = nil
    publish(targetSrc, false, false)
    TriggerClientEvent('qbpolice:client:cuffed', targetSrc, false, false)
end

---@param officerSrc integer
---@param targetSrc integer
---@return boolean ok
---@return string|nil err
---@return string|nil info `refreshed` when the target was already cuffed and the restraint was re-applied.
function Police.cuff(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if officerSrc == targetSrc then return false, 'cannot cuff yourself' end
    if Police.isCuffed(officerSrc) then return false, 'you are restrained' end
    if not exports.kora_core:getPlayerData(targetSrc) then return false, 'target not found' end
    local already = Police.isCuffed(targetSrc)
    if already and Config.cuff.recuffRefreshes == false then return false, 'already cuffed' end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end

    restrain(targetSrc, false, officerSrc)
    return true, nil, already and 'refreshed' or nil
end

---@param requesterSrc integer Officer, the cuffed player releasing themself after a successful escape, or whoever soft-cuffed them (Config.cuff.cufferCanUncuff).
---@param targetSrc integer
---@return boolean, string|nil
function Police.uncuff(requesterSrc, targetSrc)
    local state = Police.cuffState[targetSrc]
    local isOfficer = Police.isPolice(requesterSrc)
    local isSelf = requesterSrc == targetSrc
    if not Police.isCuffed(targetSrc) then
        -- Nothing to release server-side, but a client that still believes it is
        -- cuffed (stale bag, missed event) is freed so the two never disagree.
        if (isOfficer or isSelf) and exports.kora_core:getPlayerData(targetSrc) then release(targetSrc) end
        return false, 'not cuffed'
    end
    local isCuffer = state ~= nil and state.soft and state.cuffer == requesterSrc and Config.cuff.cufferCanUncuff ~= false
    if not (isSelf or isOfficer or isCuffer) then return false, 'not authorised' end
    if isSelf and not (state and state.soft) then return false, 'cannot self-release a hard cuff' end
    if not isSelf and Police.distanceBetween(requesterSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end

    release(targetSrc)
    return true
end

---Soft-cuff via the `handcuffs` useable item -- usable by anyone, not just
---police. Resolves the target as the single other online player within
---Config.cuff.distance (item use carries no client-picked target). Someone who
---is already cuffed is only the target when nobody uncuffed is in reach, and
---then the restraint is re-applied (or refused with `already cuffed` when
---Config.cuff.recuffRefreshes is off).
---@param src integer
---@return boolean ok
---@return string|nil err
---@return string|nil info
function Police.softCuffNearby(src)
    if not exports.kora_core:hasItem(src, 'handcuffs') then return false, 'handcuffs required' end
    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return false, 'no ped' end

    local free, restrained = {}, {}
    for _, other in ipairs(exports.kora_core:getPlayers()) do
        if other ~= src and Police.distanceBetween(src, other) <= Config.cuff.distance then
            local list = Police.isCuffed(other) and restrained or free
            list[#list + 1] = other
        end
    end

    local candidates = free
    if #free == 0 and #restrained > 0 then
        if Config.cuff.recuffRefreshes == false then return false, 'already cuffed' end
        candidates = restrained
    end
    if #candidates == 0 then return false, 'no one nearby to cuff' end
    if #candidates > 1 then return false, 'too many people nearby -- move closer to just one target' end

    local target = candidates[1]
    local already = Police.isCuffed(target)
    restrain(target, true, src)
    return true, nil, already and 'refreshed' or nil
end

exports.kora_core:createUseable('handcuffs', function(src)
    local ok, err, info = Police.softCuffNearby(src)
    if not ok then Police.notify(src, Police.cuffRefusal(err)) elseif info then Police.notify(src, Police.cuffRefusal(info), 'inform') end
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
    local ok, err, info = Police.cuff(source, tonumber(target))
    if not ok then Police.notify(source, Police.cuffRefusal(err)) elseif info then Police.notify(source, Police.cuffRefusal(info), 'inform') end
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

-- Restores the restraint after a login or a restart of this resource. The
-- metadata persists with the character, so without this a cuffed player who
-- relogged was still cuffed server-side while their client was free. The soft
-- flag survives a restart of this resource on the bag; after a relog the cuff
-- comes back as a hard one. Config.cuff.restoreOnLogin = false releases instead.
---@param src integer
local function syncPlayer(src)
    if not exports.kora_core:getPlayerData(src) then return end
    if not Police.isCuffed(src) then
        publish(src, false, false)
        return
    end
    if Config.cuff.restoreOnLogin == false then return release(src) end
    local player = Player(src)
    local bag = player and player.state
    local state = Police.cuffState[src]
    restrain(src, state ~= nil and state.soft or (bag ~= nil and bag[SOFT_KEY] == true), nil)
end

AddEventHandler('qbcore:server:playerLoaded', syncPlayer)
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, src in ipairs(exports.kora_core:getPlayers()) do syncPlayer(src) end
end)

AddEventHandler('playerDropped', function()
    Police.cuffState[source] = nil
end)

-- A client can write its own player bag; whatever it writes, the bag is put back
-- to what the server holds.
if AddStateBagChangeHandler then
    AddStateBagChangeHandler(STATE_KEY, nil, function(bagName, _, value)
        local src = GetPlayerFromStateBagName(bagName)
        if not src or src == 0 or not exports.kora_core:getPlayerData(src) then return end
        local cuffed = Police.isCuffed(src)
        if (value == true) ~= cuffed then
            local state = Police.cuffState[src]
            publish(src, cuffed, state ~= nil and state.soft or false)
        end
    end)
end
