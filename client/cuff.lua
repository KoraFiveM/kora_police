-- Cuff/uncuff targeting, plus the visual/control side of being cuffed
-- (animation, disabled weapons/sprint/targeting) for whichever local player the
-- state actually applies to, and both sides of the cuff/uncuff animations
-- (Config.cuff.anims). The cuffed state itself comes from the server (state bag
-- + event), never from the local animation. The handcuffs prop on every cuffed
-- player, this one included, is client/cuff_prop.lua.

local CUFF_DICT, CUFF_CLIP = 'mp_arresting', 'idle'
local controlLease = nil
local watching = false

local confirmRequested = false
-- The cuff animation/handcuffed flag went on this player's ped and has not been taken off.
local animApplied = false
-- The paired cuff clip (Config.cuff.anims.cuff.suspect) on this ped: { dict, clip, untilMs }.
local pairedAnim = nil
-- kora_target's eye was switched off by this file for the current cuff.
local targetBlocked = false

-- Bumped by every apply and every clear. Streaming the animation dictionary can
-- take frames, and each cuffStateChanged handler runs in its own coroutine, so
-- an uncuff can land while a cuff is still loading. Whatever comes back from a
-- load to a newer version (or to a free player) does nothing.
local visualsVersion = 0

local function stillCuffed(version)
    return Police.cuffed and version == visualsVersion
end

---The ped is nil/0 until kora_lib's cache has one (joining, loading screen) and
---can stop existing between two calls (respawn, model change).
local function validPed(ped)
    return type(ped) == 'number' and ped ~= 0 and DoesEntityExist(ped)
end

local function ownServerId()
    return GetPlayerServerId(Kora.cache.playerId())
end

-- kora_ambulance publishes `emsDown = false` for every living player (at login
-- and revive), so the value has to be read through Police.isDownValue: a plain
-- `~= 'alive'` test called everyone downed and no cuff/uncuff clip ever played.
local function isDowned()
    return Police.isDownValue(LocalPlayer.state.emsDown)
end

---On foot, alive and in control of the ped: the only time a one-off cuff/uncuff
---clip is played. A seated, downed or ragdolling ped keeps its own animation.
local function canPlayActionAnim(ped)
    return validPed(ped) and not Kora.cache.vehicle() and not Kora.cache.isDead() and not isDowned() and not IsPedRagdoll(ped)
end

---@param action 'cuff'|'uncuff'
---@param side 'officer'|'suspect'
---@return table|nil
local function actionAnim(action, side)
    local anims = Config.cuff.anims
    local set = type(anims) == 'table' and anims[action]
    local anim = type(set) == 'table' and set[side]
    if type(anim) ~= 'table' or type(anim.dict) ~= 'string' or type(anim.clip) ~= 'string' then return nil end
    return anim
end

---Streams a Config.cuff.anims clip in through kora_lib (with its timeout). A
---dictionary that does not exist is a config error, not a reason to fail the cuff.
local function loadActionAnim(anim)
    local ok, loaded = pcall(Kora.stream.loadAnimDict, anim.dict)
    return ok and loaded ~= false and loaded ~= nil
end

---Plays a loaded Config.cuff.anims clip on `ped` and releases the dictionary
---(the playing clip keeps what it needs). `duration` > 0 cuts it there (the
---cuff clips stop at 3043 ms): passed to TaskPlayAnim and enforced by a one-off
---timer that stops the clip if it is still on the ped; -1 plays the clip once
---to its end.
---@return integer ms how long it plays
local function startActionAnim(ped, anim)
    local duration = math.floor(tonumber(anim.duration) or -1)
    if duration <= 0 then duration = -1 end
    local ms = duration
    if ms < 0 then ms = math.floor((tonumber(GetAnimDuration(anim.dict, anim.clip)) or 0) * 1000) end
    TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, duration, math.floor(tonumber(anim.flag) or 0), 0.0, false, false, false)
    RemoveAnimDict(anim.dict)
    if duration > 0 then
        SetTimeout(duration, function()
            if DoesEntityExist(ped) and IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then
                StopAnimTask(ped, anim.dict, anim.clip, 8.0)
            end
        end)
    end
    return ms
end

---Holds the local ped where the paired clip expects it while it starts:
---attached to the officer (`attach.bone`: 0 = the ped root, else a ped bone id)
---at `attach.offset` in the officer's frame (+y = in front of them) turned by
---`attach.rotation`, and let go after `attach.ms`. The suspect's own client
---attaches its own ped, as an escort does, so every client sees it. Skipped when
---the officer is not in scope or not in reach, and for a ped that is already
---attached (escorted, carried).
local function attachToOfficer(ped, officerSrc, attach)
    if type(attach) ~= 'table' or IsEntityAttached(ped) then return end
    local player = GetPlayerFromServerId(officerSrc)
    if not player or player == -1 then return end
    local officerPed = GetPlayerPed(player)
    if not validPed(officerPed) or officerPed == ped then return end
    local there, here = GetEntityCoords(officerPed), GetEntityCoords(ped)
    local dx, dy, dz = there.x - here.x, there.y - here.y, there.z - here.z
    if math.sqrt(dx * dx + dy * dy + dz * dz) > (tonumber(Config.cuff.distance) or 2.5) + 1.0 then return end
    local offset, rotation = attach.offset or {}, attach.rotation or {}
    local bone = math.floor(tonumber(attach.bone) or 0)
    AttachEntityToEntity(ped, officerPed, bone == 0 and 0 or GetPedBoneIndex(officerPed, bone),
        offset.x or 0.0, offset.y or 0.0, offset.z or 0.0, rotation.x or 0.0, rotation.y or 0.0, rotation.z or 0.0,
        false, false, false, false, 2, true)
    SetTimeout(math.max(0, math.floor(tonumber(attach.ms) or 950)), function()
        -- An escort that started meanwhile owns the attachment now.
        if Police.escortOfficer or not DoesEntityExist(ped) then return end
        if IsEntityAttachedToEntity(ped, officerPed) then DetachEntity(ped, true, false) end
    end)
end

-- Nothing tells us when another script (an emote, a scenario, a progress bar)
-- replaces the cuff animation, so while cuffed it is checked every
-- Config.cuff.animCheckInterval ms (never below 250) and put back. The animation
-- is played with the native directly: Kora.anim.play refuses to start while another
-- resource owns the ped's animation, which is exactly when it has to be restored.
---@return boolean played
local function playCuffAnim(ped, version)
    if not validPed(ped) or not Kora.stream.loadAnimDict(CUFF_DICT) then return false end
    if not stillCuffed(version) or not validPed(ped) then return false end
    TaskPlayAnim(ped, CUFF_DICT, CUFF_CLIP, 8.0, 8.0, -1, 49, 0.0, false, false, false)
    SetEnableHandcuffs(ped, true)
    animApplied = true
    return true
end

---The suspect's half of the paired cuff animation, when the server named the
---officer who put the cuffs on. The cuffed idle takes over when it ends.
---@return boolean played
local function playPairedCuff(ped, version, officerSrc)
    local anim = actionAnim('cuff', 'suspect')
    if not anim or not officerSrc or not canPlayActionAnim(ped) then return false end
    if not loadActionAnim(anim) then return false end
    if not stillCuffed(version) or not validPed(ped) then RemoveAnimDict(anim.dict); return false end
    -- The cuffed idle (an upper-body task, already on when the bag arrived before
    -- the event) would hold the arms behind the back over the paired clip.
    if IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_CLIP, 3) then StopAnimTask(ped, CUFF_DICT, CUFF_CLIP, 8.0) end
    attachToOfficer(ped, officerSrc, anim.attach)
    local ms = startActionAnim(ped, anim)
    SetEnableHandcuffs(ped, true)
    animApplied = true
    pairedAnim = { dict = anim.dict, clip = anim.clip, untilMs = GetGameTimer() + ms }
    CreateThread(function()
        Wait(ms)
        if not stillCuffed(version) then return end
        pairedAnim = nil
        playCuffAnim(Kora.cache.ped(), version)
    end)
    return true
end

---Takes the cuff animation and the handcuffed ped flag off the local ped. The
---owning client stopping it is what every other client sees. The ped's tasks are
---only cleared when the cuff was actually on it, so freeing a client that was
---never cuffed does not cancel whatever it is doing.
local function stopCuffAnim(ped)
    local hadCuff = animApplied
    local paired = pairedAnim
    animApplied, pairedAnim = false, nil
    if not validPed(ped) then return end
    SetEnableHandcuffs(ped, false)
    if paired then StopAnimTask(ped, paired.dict, paired.clip, 8.0) end
    if not hadCuff and not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_CLIP, 3) then return end
    StopAnimTask(ped, CUFF_DICT, CUFF_CLIP, 8.0)
    -- Flag 49 plays the cuff clip as a secondary (upper-body) task.
    ClearPedSecondaryTask(ped)
    if Config.cuff.clearTasksOnUncuff == false or Kora.cache.vehicle() or Kora.cache.isDead() or isDowned() then return end
    ClearPedTasks(ped)
end

-- kora_target only gates its eye on its own enabled flag (and kora_multichar's
-- mode and death); nothing else tells it the player is cuffed, and the Alt key
-- is a key mapping the control lease cannot disable. So while cuffed the eye is
-- switched off through its setEnabled export (which also closes an open option
-- menu), and switched back on at the uncuff only when this file switched it off.
local function setTargetBlocked(blocked)
    if blocked and Config.cuff.blockTargeting == false then return end
    if blocked == targetBlocked then return end
    if GetResourceState('kora_target') ~= 'started' then targetBlocked = false; return end
    if pcall(function() exports.kora_target:setEnabled(not blocked) end) then targetBlocked = blocked end
end

---One-offs at the start of a cuff: nothing in hand, the phone put away.
local function onCuffStart(ped)
    if Config.cuff.holsterWeapon ~= false and validPed(ped) then
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    end
    if Config.cuff.closePhone ~= false and GetResourceState('kora_phone') == 'started' then
        pcall(function() exports.kora_phone:close() end)
    end
end

---Asks the server once per cuff whether it really holds one for this player
---(server/cuff.lua corrects a stale bag on its side) and applies the answer, so a
---replicated cuff the server does not stand behind never leaves the player locked
---out of their inventory with nothing to show for it.
local function confirmWithServer()
    if confirmRequested or Config.cuff.verifyWithServer == false then return end
    confirmRequested = true
    CreateThread(function()
        local ok, cuffed, soft = pcall(Kora.callback.trigger, 'kora_police:server:resyncCuff')
        if ok and type(cuffed) == 'boolean' then Police.syncCuffState(cuffed, soft) end
    end)
end

---Puts back the cuff animation the ped lost. Stays out of the way of the paired
---cuff clip while it plays, of a downed/dead player, whose animation belongs to
---the medical resource, and of a ragdoll.
local function restoreCuffed()
    if pairedAnim and GetGameTimer() < pairedAnim.untilMs then return end
    local version = visualsVersion
    local ped = Kora.cache.ped()
    if not validPed(ped) or Kora.cache.isDead() or IsPedRagdoll(ped) or isDowned() then return end
    if not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_CLIP, 3) then playCuffAnim(ped, version) end
end

local function startCuffWatch()
    if watching then return end
    watching = true
    CreateThread(function()
        while Police.cuffed do
            Wait(math.max(250, tonumber(Config.cuff.animCheckInterval) or 500))
            if Police.cuffed then restoreCuffed() end
        end
        watching = false
    end)
end

---Everything a cuff put on, taken off. Safe to run when nothing is applied, so
---every uncuff (event, bag, server answer) runs it in full.
local function clearCuffedVisuals()
    confirmRequested = false
    if controlLease then Kora.controls.release(controlLease); controlLease = nil end
    setTargetBlocked(false)
    Police.cuffProps.set(ownServerId(), false)
    stopCuffAnim(Kora.cache.ped())
    RemoveAnimDict(CUFF_DICT)

    -- One deferred re-check, not a loop: anything that still put the cuff
    -- animation back after the uncuff is taken off again.
    local delay = tonumber(Config.cuff.uncuffRecheckMs) or 0
    if delay <= 0 then return end
    local version = visualsVersion
    SetTimeout(delay, function()
        if Police.cuffed or version ~= visualsVersion then return end
        Police.cuffProps.set(ownServerId(), false)
        local ped = Kora.cache.ped()
        if validPed(ped) and (animApplied or IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_CLIP, 3)) then stopCuffAnim(ped) end
    end)
end

---The freed suspect's half of the uncuff animation, when an officer (or the
---soft-cuffer) took the cuffs off.
local function playUncuffAnim(officerSrc, version)
    local anim = actionAnim('uncuff', 'suspect')
    local ped = Kora.cache.ped()
    if not anim or not officerSrc or not canPlayActionAnim(ped) then return end
    if not loadActionAnim(anim) then return end
    if Police.cuffed or version ~= visualsVersion or not validPed(ped) then RemoveAnimDict(anim.dict); return end
    attachToOfficer(ped, officerSrc, anim.attach)
    startActionAnim(ped, anim)
end

-- The disabled controls go through a kora_lib lease, whose per-frame loop exists
-- only while a lease is held, i.e. while cuffed. Without a ped yet (joining) the
-- animation follows from the cache's ped change below. `actorSrc` is the
-- officer/cuffer the server names for a fresh cuff or an uncuff: it turns on the
-- suspect's half of the paired animation.
local function applyCuffedVisuals(cuffed, _, actorSrc)
    visualsVersion = visualsVersion + 1
    local version = visualsVersion
    actorSrc = tonumber(actorSrc)
    if not (cuffed and Police.cuffed) then
        clearCuffedVisuals()
        return playUncuffAnim(actorSrc, version)
    end

    local ped = Kora.cache.ped()
    if not controlLease then
        controlLease = Kora.controls.acquire(Config.cuff.disabledControls, { disablePlayerFiring = true, ignoreWeaponWheel = true })
        onCuffStart(ped)
    end
    setTargetBlocked(true)
    Police.cuffProps.set(ownServerId(), true)
    local shown = playPairedCuff(ped, version, actorSrc)
    if not stillCuffed(version) then return end
    if not shown then shown = playCuffAnim(ped, version) end
    if not stillCuffed(version) then return end
    startCuffWatch()
    if not shown then confirmWithServer() end
end

AddEventHandler('qbpolice:client:cuffStateChanged', applyCuffedVisuals)

-- A new ped (joining, respawn, model change) has no cuff animation.
Kora.cache.onChange('ped', function()
    if Police.cuffed then restoreCuffed() end
end)

-- The officer's half of the cuff/uncuff animation. The server sends it only
-- after it accepted the cuff or uncuff; the state never depends on it.
RegisterNetEvent('kora_police:client:cuffAction', function(action)
    local anim = (action == 'cuff' or action == 'uncuff') and actionAnim(action, 'officer')
    if not anim or Police.cuffed then return end
    local ped = Kora.cache.ped()
    if not canPlayActionAnim(ped) or not loadActionAnim(anim) then return end
    if not validPed(ped) then RemoveAnimDict(anim.dict); return end
    startActionAnim(ped, anim)
end)

-- The state bag is what the server publishes (see server/cuff.lua) and what every
-- other client, the emote menu and kora_inventory read.
local function ownBag(bagName)
    return bagName == ('player:%d'):format(ownServerId())
end

---@param cuffed boolean
---@param soft boolean
local function syncFromBag(cuffed, soft)
    local wasCuffed = Police.cuffed
    Police.syncCuffState(cuffed, cuffed and soft)
    if cuffed and not wasCuffed then confirmWithServer() end
end

-- A change handler runs before the bag stores the new value: inside it,
-- LocalPlayer.state still returns the OLD value of the key that changed, so the
-- new one is taken from the change itself. Only koraCuffed decides whether the
-- player is cuffed; koraCuffedSoft (written first by the server) only refines a
-- cuff that is already on, so it can never put back a cuff an uncuff just took off.
-- Another player's bag only decides whether they wear the handcuffs prop.
Kora.state.onChange('koraCuffed', nil, function(change)
    if not ownBag(change.bagName) then
        local serverId = type(change.bagName) == 'string' and tonumber(change.bagName:match('^player:(%d+)$'))
        if serverId then Police.cuffProps.set(serverId, change.value == true) end
        return
    end
    syncFromBag(change.value == true, LocalPlayer.state.koraCuffedSoft == true)
end)

Kora.state.onChange('koraCuffedSoft', nil, function(change)
    if not ownBag(change.bagName) or not Police.cuffed then return end
    Police.syncCuffState(true, change.value == true)
end)

-- Covers joining and a resource restart while already cuffed -- the bag keeps
-- its value, so no change handler fires for it.
syncFromBag(LocalPlayer.state.koraCuffed == true, LocalPlayer.state.koraCuffedSoft == true)

local function nearestCuffedServerId()
    local origin = Kora.cache.coords()
    local best, bestDistance = nil, Config.cuff.distance
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if player ~= Kora.cache.playerId() and ped ~= 0 and Police.isPedCuffed(ped) then
            local distance = #(GetEntityCoords(ped) - origin)
            if distance <= bestDistance then best, bestDistance = GetPlayerServerId(player), distance end
        end
    end
    return best
end

local uncuffCommand = Config.cuff.uncuffCommand
if type(uncuffCommand) == 'string' and uncuffCommand ~= '' then
    RegisterCommand(uncuffCommand, function()
        local target = nearestCuffedServerId()
        if not target then return Police.notify('No cuffed player nearby.', 'error') end
        TriggerServerEvent('qbpolice:server:uncuff', target)
    end, false)
end

local function registerCuffTargets()
    Police.target.reset('cuff')
    Police.target.global('cuff', 'player', {
        {
            label = 'Cuff',
            icon = 'lock',
            canInteract = function(entity)
                return Police.isOnDuty() and not Police.isPedCuffed(entity)
            end,
            onSelect = function(entity)
                local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId <= 0 then
                    return Police.notify('No player to cuff.', 'error')
                end
                TriggerServerEvent('qbpolice:server:cuff', targetServerId)
            end,
        },
        {
            label = 'Uncuff',
            icon = 'lock-open',
            canInteract = function(entity)
                return Police.isOnDuty() and Police.isPedCuffed(entity)
            end,
            onSelect = function(entity)
                local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId <= 0 then
                    return Police.notify('No player to uncuff.', 'error')
                end
                TriggerServerEvent('qbpolice:server:uncuff', targetServerId)
            end,
        },
    }, Config.cuff.distance)
end
registerCuffTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= 'kora_target' then return end
    registerCuffTargets()
    -- A fresh kora_target starts with its eye on.
    targetBlocked = false
    if Police.cuffed then setTargetBlocked(true) end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == 'kora_target' then
        targetBlocked = false
    elseif resourceName == GetCurrentResourceName() then
        -- Nobody would switch the eye back on after this resource is gone.
        setTargetBlocked(false)
    end
end)
