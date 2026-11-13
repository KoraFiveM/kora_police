-- Restrain/release. `soft` cuffs (via the `handcuffs` useable item, usable by
-- anyone) can be escaped with the ported qbx_police-style WASD skillcheck;
-- `hard` cuffs (via an on-duty officer's own action) cannot -- only an
-- officer or an /unjail-equivalent release clears those.

-- src -> { soft = boolean, officer = integer|nil, cuffer = integer|nil, attemptsUsed = integer, cooldownUntil = integer }
Police.cuffState = Police.cuffState or {}

-- The restraint is stored once (kora_core metadata `ishandcuffed`, which is what
-- Police.isCuffed reads) and mirrored to the replicated player state bags below
-- by `restrain`/`release`, the only writers. Clients, the emote menu and
-- kora_inventory only ever read them; a client write is reverted. The metadata
-- persists with the character, but a cuff only lasts for the session it was put
-- on in (see syncLogin below).
local STATE_KEY, SOFT_KEY = 'koraCuffed', 'koraCuffedSoft'

-- Player-facing wording for a refused cuff/uncuff, so a refusal is never silent.
local REFUSALS = {
    ['not an on-duty officer'] = Kora.lang('Notify.on_duty_police'),
    ['cannot cuff yourself'] = Kora.lang('Notify.cuff_self_refused'),
    ['target not found'] = Kora.lang('Notify.player_not_found'),
    ['already cuffed'] = Kora.lang('Notify.already_cuffed_notice'),
    ['refreshed'] = Kora.lang('Notify.cuffs_refreshed_notice'),
    ['too far away'] = Kora.lang('Notify.too_far_away'),
    ['not cuffed'] = Kora.lang('Notify.target_not_cuffed'),
    ['not authorised'] = Kora.lang('Notify.not_allowed'),
    ['you are restrained'] = Kora.lang('Notify.restrained_action'),
    ['handcuffs required'] = Kora.lang('Notify.need_handcuffs'),
}
---@param err string|nil
---@return string
function Police.cuffRefusal(err)
    return REFUSALS[err] or err or Kora.lang('Notify.action_failed')
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

---Tells `src` they were cuffed/uncuffed, with the Config.cuff.notify text for
---`key` ('' or false sends nothing).
---@param src integer
---@param key 'cuffed'|'uncuffed'
---@param type_ string
local function notifyCuff(src, key, type_)
    local messages = Config.cuff.notify
    local message = type(messages) == 'table' and messages[key]
    if type(message) == 'string' and message ~= '' then Police.notify(src, message, type_) end
end

---Puts the restraint on `targetSrc`, or re-applies it when they are already cuffed
---(the state is written and replicated again, so a client that lost the cuff
---animation gets it back). A hard cuff is never downgraded by a soft one; an
---officer's cuff upgrades a soft one. A fresh cuff by a player plays the paired
---cuff animation (Config.cuff.anims.cuff) on both of them and tells the suspect;
---it is only cosmetic, the state above is already in force.
---@param targetSrc integer
---@param soft boolean
---@param cuffer integer|nil Who applied it.
---@return table state
local function restrain(targetSrc, soft, cuffer)
    local state = Police.cuffState[targetSrc]
    local fresh = state == nil and not Police.isCuffed(targetSrc)
    local actor = fresh and cuffer ~= targetSrc and cuffer or nil
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
    TriggerClientEvent('kora_police:client:cuffed', targetSrc, true, state.soft, actor)
    if actor then
        TriggerClientEvent('kora_police:client:cuffAction', actor, 'cuff', targetSrc)
        notifyCuff(targetSrc, 'cuffed', 'warning')
    end
    return state
end

---@param targetSrc integer
---@param actorSrc integer|nil Another player who took the cuffs off (officer or soft-cuffer): plays the uncuff animation (Config.cuff.anims.uncuff) on both and tells the freed player.
local function release(targetSrc, actorSrc)
    if actorSrc == targetSrc then actorSrc = nil end
    exports.kora_core:setMetaData(targetSrc, 'ishandcuffed', false)
    Police.cuffState[targetSrc] = nil
    publish(targetSrc, false, false)
    TriggerClientEvent('kora_police:client:cuffed', targetSrc, false, false, actorSrc)
    if actorSrc then
        TriggerClientEvent('kora_police:client:cuffAction', actorSrc, 'uncuff', targetSrc)
        notifyCuff(targetSrc, 'uncuffed', 'success')
    end
    -- An escort only exists for a cuffed suspect (Police.escort refuses anyone
    -- else); left running it keeps the freed player attached to the officer.
    local officer = Police.escorted and Police.escorted[targetSrc]
    if officer and Police.deEscort then Police.deEscort(officer, targetSrc) end
end

---@param officerSrc integer
---@param targetSrc integer
---@return boolean ok
---@return string|nil err
---@return string|nil info `refreshed` when the target was already cuffed and the restraint was re-applied.
function Police.cuff(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, Kora.lang('Notify.on_duty_police') end
    if officerSrc == targetSrc then return false, Kora.lang('Notify.cuff_self_refused') end
    if Police.isCuffed(officerSrc) then return false, Kora.lang('Notify.restrained_action') end
    if not exports.kora_core:getPlayerData(targetSrc) then return false, Kora.lang('Notify.player_not_found') end
    local already = Police.isCuffed(targetSrc)
    if already and Config.cuff.recuffRefreshes == false then return false, Kora.lang('Notify.already_cuffed_notice') end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, Kora.lang('Notify.too_far_away') end

    restrain(targetSrc, false, officerSrc)
    return true, nil, already and 'refreshed' or nil
end

---@param requesterSrc integer Officer, the cuffed player releasing themself after a successful escape, or whoever soft-cuffed them (Config.cuff.cufferCanUncuff).
---@param targetSrc integer
---@param opts? { silent?: boolean } silent: no uncuff animation and no notification (a release on booking).
---@return boolean, string|nil
function Police.uncuff(requesterSrc, targetSrc, opts)
    local state = Police.cuffState[targetSrc]
    local isOfficer = Police.isPolice(requesterSrc)
    local isSelf = requesterSrc == targetSrc
    if not Police.isCuffed(targetSrc) then
        -- Nothing to release server-side, but a client that still believes it is
        -- cuffed (stale bag, missed event) is freed so the two never disagree.
        if (isOfficer or isSelf) and exports.kora_core:getPlayerData(targetSrc) then release(targetSrc) end
        return false, Kora.lang('Notify.target_not_cuffed')
    end
    local isCuffer = state ~= nil and state.soft and state.cuffer == requesterSrc and Config.cuff.cufferCanUncuff ~= false
    if not (isSelf or isOfficer or isCuffer) then return false, Kora.lang('Notify.not_allowed') end
    if isSelf and not (state and state.soft) then return false, Kora.lang('Notify.cannot_self_release_a_hard_cuff') end
    if not isSelf and Police.distanceBetween(requesterSrc, targetSrc) > Config.cuff.distance then return false, Kora.lang('Notify.too_far_away') end

    release(targetSrc, not (opts and opts.silent) and requesterSrc or nil)
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
    if not exports.kora_core:hasItem(src, 'handcuffs') then return false, Kora.lang('Notify.need_handcuffs') end
    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return false, Kora.lang('Notify.no_ped') end

    local free, restrained = {}, {}
    for _, other in ipairs(exports.kora_core:getPlayers()) do
        if other ~= src and Police.distanceBetween(src, other) <= Config.cuff.distance then
            local list = Police.isCuffed(other) and restrained or free
            list[#list + 1] = other
        end
    end

    local candidates = free
    if #free == 0 and #restrained > 0 then
        if Config.cuff.recuffRefreshes == false then return false, Kora.lang('Notify.already_cuffed_notice') end
        candidates = restrained
    end
    if #candidates == 0 then return false, Kora.lang('Notify.no_one_to_cuff') end
    if #candidates > 1 then return false, Kora.lang('Notify.too_many_targets') end

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
    if not state or not state.soft then return false, Kora.lang('Notify.not_soft_cuffed') end
    if GetGameTimer() < state.cooldownUntil then return false, Kora.lang('Notify.on_cooldown') end
    if state.attemptsUsed >= Config.cuff.breakCuffsAttempts then return false, Kora.lang('Notify.no_attempts_remaining') end
    local authorization = state.breakAuthorization
    state.breakAuthorization = nil
    if not authorization or not Kora.minigames.consumeProof(src, proof,
        Config.minigames.breakCuffs.type, authorization) then
        return false, Kora.lang('Notify.invalid_minigame_proof')
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
    if not state or not state.soft then return nil, Kora.lang('Notify.not_soft_cuffed') end
    if state.breakAuthorization then return nil, Kora.lang('Notify.attempt_in_progress') end
    if GetGameTimer() < state.cooldownUntil then return nil, Kora.lang('Notify.on_cooldown') end
    if state.attemptsUsed >= Config.cuff.breakCuffsAttempts then return nil, Kora.lang('Notify.no_attempts_remaining') end

    local attempt = state.attemptsUsed + 1
    local difficulty = Config.cuff.breakCuffsDifficulty[math.min(attempt, #Config.cuff.breakCuffsDifficulty)]
    local opts = Config.minigames.breakCuffs.opts[difficulty] or Config.minigames.breakCuffs.opts.medium
    local authorization = Kora.minigames.authorizeProof(src, Config.minigames.breakCuffs.type, opts)
    if not authorization then return nil, Kora.lang('Notify.escape_not_authorized') end
    state.breakAuthorization = authorization
    return authorization
end

-- `source` is only valid until a handler first yields, so each captures it.
RegisterNetEvent('kora_police:server:cuff', function(target)
    local src = source
    local ok, err, info = Police.cuff(src, tonumber(target))
    if not ok then Police.notify(src, Police.cuffRefusal(err)) elseif info then Police.notify(src, Police.cuffRefusal(info), 'inform') end
end)
RegisterNetEvent('kora_police:server:uncuff', function(target)
    local src = source
    local ok, err = Police.uncuff(src, tonumber(target))
    if not ok then Police.notify(src, Police.cuffRefusal(err)) end
end)
RegisterNetEvent('kora_police:server:breakCuffsResult', function(proof)
    local src = source
    local escaped = type(proof) == 'string' and Police.breakCuffs(src, proof)
    if escaped then
        Police.notify(src, 'You broke free!', 'success')
    else
        Police.breakCuffsFailed(src)
    end
end)

Kora.callback.register('kora_police:server:beginBreakCuffs', function(src)
    return Police.beginBreakCuffs(src)
end)

Kora.callback.register('kora_police:server:getCuffed', function(src, target)
    return Police.isCuffed(target or src)
end)

-- A cuff belongs to the session it was put on in: Police.cuffState holds it and
-- is dropped on logout, character switch and disconnect. The `ishandcuffed`
-- metadata still persists with the character, so at login a stored cuff with no
-- live session behind it is stale and is cleared -- unless
-- Config.cuff.restoreOnLogin (anti-combat-log, off by default) brings it back as
-- a hard cuff.
---@param src integer
local function syncLogin(src)
    if not exports.kora_core:getPlayerData(src) then return end
    local live = Police.cuffState[src]
    if live then return restrain(src, live.soft, live.cuffer) end
    if Police.isCuffed(src) and Config.cuff.restoreOnLogin == true then return restrain(src, false, nil) end
    local player = Player(src)
    local bag = player and player.state
    if Police.isCuffed(src) or (bag ~= nil and bag[STATE_KEY] == true) then return release(src) end
    publish(src, false, false)
end

-- A restart of this resource loses Police.cuffState but not the session: a
-- player whose bag still says cuffed was cuffed by the previous instance and
-- stays cuffed (soft flag included).
---@param src integer
local function syncRunning(src)
    if not exports.kora_core:getPlayerData(src) then return end
    local player = Player(src)
    local bag = player and player.state
    local bagCuffed = bag ~= nil and bag[STATE_KEY] == true
    if Police.isCuffed(src) and (bagCuffed or Config.cuff.restoreOnLogin == true) then
        return restrain(src, bagCuffed and bag[SOFT_KEY] == true, nil)
    end
    if Police.isCuffed(src) or bagCuffed then return release(src) end
    publish(src, false, false)
end

AddEventHandler('kora_core:server:playerLoaded', syncLogin)
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, src in ipairs(exports.kora_core:getPlayers()) do syncRunning(src) end
end)

-- Logout/character switch (kora_core fires the unload for a disconnect too).
-- The metadata is left alone: kora_core has already saved it, and the next
-- login decides what a stored cuff means.
---@param src integer
local function endSession(src)
    local wasCuffed = Police.cuffState[src] ~= nil
    Police.cuffState[src] = nil
    publish(src, false, false)
    if wasCuffed then TriggerClientEvent('kora_police:client:cuffed', src, false, false) end
end

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) endSession(tonumber(src) or source) end)
AddEventHandler('playerDropped', function()
    local src = source
    -- The unload above normally cleared the bag already; without it every client
    -- is told directly, so nobody keeps drawing handcuffs on a player who left.
    if Police.cuffState[src] then TriggerClientEvent('kora_police:client:cuffedPlayerGone', -1, src) end
    Police.cuffState[src] = nil
end)

---Whether `src` is cuffed in this session: the live restraint and the stored
---metadata agree.
---@param src integer
---@return boolean cuffed
---@return boolean soft
local function sessionCuffed(src)
    local state = Police.cuffState[src]
    if state == nil or not Police.isCuffed(src) then return false, false end
    return true, state.soft == true
end

-- A client that sees itself cuffed asks here before it stays locked. The answer is
-- the session state; a bag or metadata that disagrees with it is corrected.
Kora.callback.register('kora_police:server:resyncCuff', function(src)
    if not exports.kora_core:getPlayerData(src) then
        publish(src, false, false)
        return false, false
    end
    local cuffed, soft = sessionCuffed(src)
    if not cuffed then
        if Police.cuffState[src] or Police.isCuffed(src) or Player(src).state[STATE_KEY] == true then release(src) end
        return false, false
    end
    local bag = Player(src).state
    if bag[STATE_KEY] ~= true or (bag[SOFT_KEY] == true) ~= soft then publish(src, true, soft) end
    return true, soft
end)

-- Who is cuffed right now, for a client that just loaded: their bags hold the
-- value, so it sees no change for them (client/cuff_prop.lua draws their cuffs).
Kora.callback.register('kora_police:server:cuffedPlayers', function()
    local list = {}
    for src in pairs(Police.cuffState) do
        local player = Player(src)
        if player and player.state and player.state[STATE_KEY] == true then list[#list + 1] = src end
    end
    return list
end)

-- A client can write its own player bag; whatever it writes, the bag is put back
-- to what the server holds for the session.
if AddStateBagChangeHandler then
    AddStateBagChangeHandler(STATE_KEY, nil, function(bagName, _, value)
        local src = GetPlayerFromStateBagName(bagName)
        if not src or src == 0 then return end
        local cuffed, soft = sessionCuffed(src)
        if (value == true) ~= cuffed then publish(src, cuffed, soft) end
    end)
end
