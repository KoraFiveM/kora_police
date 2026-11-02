-- Cuff/uncuff targeting, plus the visual/control side of being cuffed
-- (animation, attached prop, disabled weapons/sprint) for whichever local
-- player the state actually applies to. The cuffed state itself comes from the
-- server (state bag + event), never from the local animation.

local CUFF_DICT, CUFF_CLIP = 'mp_arresting', 'idle'
local CUFF_PROP_MODEL, CUFF_PROP_BONE = 'p_cs_cuffs_01', 'SKEL_L_Hand'
local attachedProp = nil
local controlLease = nil
local watching = false

local confirmRequested = false
-- The cuff animation/handcuffed flag went on this player's ped and has not been taken off.
local animApplied = false

-- Bumped by every apply and every clear. Streaming the animation dictionary or
-- the cuffs model can take frames, and each cuffStateChanged handler runs in its
-- own coroutine, so an uncuff can land while a cuff is still loading. Whatever
-- comes back from a load to a newer version (or to a free player) does nothing.
local visualsVersion = 0

local function stillCuffed(version)
    return Police.cuffed and version == visualsVersion
end

---The ped is nil/0 until kora_lib's cache has one (joining, loading screen) and
---can stop existing between two calls (respawn, model change).
local function validPed(ped)
    return type(ped) == 'number' and ped ~= 0 and DoesEntityExist(ped)
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

local function removeCuffProp()
    if attachedProp then pcall(Kora.anim.detachProp, attachedProp); attachedProp = nil end
end

-- The prop is cosmetic: Kora.anim.attachProp raises on a ped that is gone, and
-- that must never take the cuff state or the rest of the visuals down with it.
---@return boolean attached
local function ensureCuffProp(ped, version)
    if not validPed(ped) then return false end
    if attachedProp and DoesEntityExist(attachedProp) and IsEntityAttachedToEntity(attachedProp, ped) then return true end
    removeCuffProp()
    local ok, prop = pcall(Kora.anim.attachProp, ped, CUFF_PROP_MODEL, CUFF_PROP_BONE, { x = 0.0, y = 0.0, z = 0.0 })
    if not ok or not prop then return false end
    -- Uncuffed while the model streamed in, or another apply attached one first.
    if not stillCuffed(version) or attachedProp then
        pcall(Kora.anim.detachProp, prop)
        return attachedProp ~= nil and stillCuffed(version)
    end
    attachedProp = prop
    return true
end

---Takes the cuff animation and the handcuffed ped flag off the local ped. The
---owning client stopping it is what every other client sees. The ped's tasks are
---only cleared when the cuff was actually on it, so freeing a client that was
---never cuffed does not cancel whatever it is doing.
local function stopCuffAnim(ped)
    local hadCuff = animApplied
    animApplied = false
    if not validPed(ped) then return end
    SetEnableHandcuffs(ped, false)
    if not hadCuff and not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_CLIP, 3) then return end
    StopAnimTask(ped, CUFF_DICT, CUFF_CLIP, 8.0)
    -- Flag 49 plays the cuff clip as a secondary (upper-body) task.
    ClearPedSecondaryTask(ped)
    if Config.cuff.clearTasksOnUncuff == false or Kora.cache.vehicle() or Kora.cache.isDead() then return end
    local down = LocalPlayer.state.emsDown
    if down ~= nil and down ~= 'alive' then return end
    ClearPedTasks(ped)
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

---Puts back whatever the cuffed ped lost: the animation and the cuffs prop.
---Stays out of the way of a downed/dead player, whose animation belongs to the
---medical resource, and of a ragdoll.
local function restoreCuffed()
    local version = visualsVersion
    local ped = Kora.cache.ped()
    if not validPed(ped) or Kora.cache.isDead() or IsPedRagdoll(ped) then return end
    local down = LocalPlayer.state.emsDown
    if down ~= nil and down ~= 'alive' then return end
    if not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_CLIP, 3) then playCuffAnim(ped, version) end
    if stillCuffed(version) then ensureCuffProp(ped, version) end
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
    removeCuffProp()
    stopCuffAnim(Kora.cache.ped())
    RemoveAnimDict(CUFF_DICT)

    -- One deferred re-check, not a loop: anything that still put the cuff
    -- animation back after the uncuff is taken off again.
    local delay = tonumber(Config.cuff.uncuffRecheckMs) or 0
    if delay <= 0 then return end
    local version = visualsVersion
    SetTimeout(delay, function()
        if Police.cuffed or version ~= visualsVersion then return end
        removeCuffProp()
        local ped = Kora.cache.ped()
        if validPed(ped) and (animApplied or IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_CLIP, 3)) then stopCuffAnim(ped) end
    end)
end

-- The disabled controls go through a kora_lib lease, whose per-frame loop exists
-- only while a lease is held, i.e. while cuffed. Without a ped yet (joining) the
-- animation and prop follow from the cache's ped change below.
local function applyCuffedVisuals(cuffed)
    visualsVersion = visualsVersion + 1
    local version = visualsVersion
    if not (cuffed and Police.cuffed) then return clearCuffedVisuals() end

    if not controlLease then
        controlLease = Kora.controls.acquire(Config.cuff.disabledControls, { disablePlayerFiring = true, ignoreWeaponWheel = true })
    end
    local ped = Kora.cache.ped()
    local shown = playCuffAnim(ped, version)
    if not stillCuffed(version) then return end
    shown = ensureCuffProp(ped, version) and shown
    if not stillCuffed(version) then return end
    startCuffWatch()
    if not shown then confirmWithServer() end
end

AddEventHandler('qbpolice:client:cuffStateChanged', applyCuffedVisuals)

-- A new ped (joining, respawn, model change) has neither the animation nor the prop.
Kora.cache.onChange('ped', function()
    if Police.cuffed then restoreCuffed() end
end)

-- The state bag is what the server publishes (see server/cuff.lua) and what every
-- other client, the emote menu and kora_inventory read.
local function ownBag(bagName)
    return bagName == ('player:%d'):format(GetPlayerServerId(Kora.cache.playerId()))
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
Kora.state.onChange('koraCuffed', nil, function(change)
    if not ownBag(change.bagName) then return end
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
    if resourceName == 'kora_target' then registerCuffTargets() end
end)
