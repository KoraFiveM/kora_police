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
local function playCuffAnim(ped)
    if not validPed(ped) or not Kora.stream.loadAnimDict(CUFF_DICT) then return false end
    TaskPlayAnim(ped, CUFF_DICT, CUFF_CLIP, 8.0, 8.0, -1, 49, 0.0, false, false, false)
    SetEnableHandcuffs(ped, true)
    return true
end

local function removeCuffProp()
    if attachedProp then pcall(Kora.anim.detachProp, attachedProp); attachedProp = nil end
end

-- The prop is cosmetic: Kora.anim.attachProp raises on a ped that is gone, and
-- that must never take the cuff state or the rest of the visuals down with it.
---@return boolean attached
local function ensureCuffProp(ped)
    if not validPed(ped) then return false end
    if attachedProp and DoesEntityExist(attachedProp) and IsEntityAttachedToEntity(attachedProp, ped) then return true end
    removeCuffProp()
    local ok, prop = pcall(Kora.anim.attachProp, ped, CUFF_PROP_MODEL, CUFF_PROP_BONE, { x = 0.0, y = 0.0, z = 0.0 })
    if ok and prop then attachedProp = prop; return true end
    return false
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
    local ped = Kora.cache.ped()
    if not validPed(ped) or Kora.cache.isDead() or IsPedRagdoll(ped) then return end
    local down = LocalPlayer.state.emsDown
    if down ~= nil and down ~= 'alive' then return end
    if not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_CLIP, 3) then playCuffAnim(ped) end
    ensureCuffProp(ped)
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

-- The disabled controls go through a kora_lib lease, whose per-frame loop exists
-- only while a lease is held, i.e. while cuffed. Without a ped yet (joining) the
-- animation and prop follow from the cache's ped change below.
local function applyCuffedVisuals(cuffed)
    local ped = Kora.cache.ped()
    if cuffed then
        if not controlLease then
            controlLease = Kora.controls.acquire(Config.cuff.disabledControls, { disablePlayerFiring = true, ignoreWeaponWheel = true })
        end
        local shown = playCuffAnim(ped)
        shown = ensureCuffProp(ped) and shown
        startCuffWatch()
        if not shown then confirmWithServer() end
    else
        confirmRequested = false
        if controlLease then Kora.controls.release(controlLease); controlLease = nil end
        removeCuffProp()
        if validPed(ped) then
            StopAnimTask(ped, CUFF_DICT, CUFF_CLIP, 8.0)
            SetEnableHandcuffs(ped, false)
        end
        RemoveAnimDict(CUFF_DICT)
    end
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

local function syncFromBag()
    local state = LocalPlayer.state
    local cuffed, wasCuffed = state.koraCuffed == true, Police.cuffed
    Police.syncCuffState(cuffed, state.koraCuffedSoft == true)
    if cuffed and not wasCuffed then confirmWithServer() end
end

for _, key in ipairs({ 'koraCuffed', 'koraCuffedSoft' }) do
    Kora.state.onChange(key, nil, function(change)
        if ownBag(change.bagName) then syncFromBag() end
    end)
end

-- Covers joining and a resource restart while already cuffed -- the bag keeps
-- its value, so no change handler fires for it.
syncFromBag()

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
