-- Cuff/uncuff targeting, plus the visual/control side of being cuffed
-- (animation, attached prop, disabled weapons/sprint) for whichever local
-- player the state actually applies to.

local CUFF_DICT, CUFF_CLIP = 'mp_arresting', 'idle'
local CUFF_PROP_MODEL, CUFF_PROP_BONE = 'p_cs_cuffs_01', 'SKEL_L_Hand'
local attachedProp = nil
local playerId = Kora.cache.playerId()

local function applyCuffedVisuals(cuffed)
    local ped = Kora.cache.ped()
    if cuffed then
        Kora.anim.play(ped, CUFF_DICT, CUFF_CLIP, { flag = 49 })
        local prop = Kora.anim.attachProp(ped, CUFF_PROP_MODEL, CUFF_PROP_BONE, { x = 0.0, y = 0.0, z = 0.0 })
        if prop then attachedProp = prop end
        SetEnableHandcuffs(ped, true)
    else
        Kora.anim.stop(ped)
        if attachedProp then Kora.anim.detachProp(attachedProp); attachedProp = nil end
        SetEnableHandcuffs(ped, false)
    end
end

-- Lazily started/stopped as the player is cuffed/uncuffed -- mirrors
-- kora_hud's client/vehicle.lua lazy tick-thread pattern -- rather than a bare
-- always-running CreateThread, so this costs nothing while not cuffed.
local function startCuffedControlThread()
    CreateThread(function()
        while true do
            if not Police.cuffed then return end
            DisableControlAction(0, 24, true)  -- attack
            DisableControlAction(0, 25, true)  -- aim
            DisableControlAction(0, 47, true)  -- weapon
            DisableControlAction(0, 58, true)  -- weapon select
            DisableControlAction(0, 21, true)  -- sprint
            DisableControlAction(0, 22, true)  -- jump
            DisablePlayerFiring(playerId, true)
            Wait(0)
        end
    end)
end

AddEventHandler('qbpolice:client:cuffStateChanged', function(cuffed)
    applyCuffedVisuals(cuffed)
    if cuffed then startCuffedControlThread() end
end)

-- Covers a resource restart while already cuffed -- onChange/event alone
-- only fires on the next actual transition.
if Police.cuffed then startCuffedControlThread() end

local function registerCuffTargets()
    Police.target.reset('cuff')
    Police.target.global('cuff', 'player', {
        {
            label = 'Cuff',
            icon = 'lock',
            canInteract = function(entity)
                return Police.isOnDuty() and not IsPedCuffed(entity)
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:cuff', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
        {
            label = 'Uncuff',
            icon = 'lock-open',
            canInteract = function(entity)
                return Police.isOnDuty() and IsPedCuffed(entity)
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:uncuff', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
    }, Config.cuff.distance)
end
registerCuffTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerCuffTargets() end
end)
