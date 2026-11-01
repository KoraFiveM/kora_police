-- Escort (suspect walks alongside/behind the officer) and drag (kidnap-style,
-- for an unconscious/uncooperative target). Not solvable with
-- Kora.anim.attachProp -- the other player owns their own networked ped, so
-- each side's OWN client issues AttachEntityToEntity on itself, driven by a
-- server relay rather than kora_police trying to move another player's entity
-- remotely. The officer's client only renders local UI state; it never
-- attaches anything on the suspect's behalf.

local ESCORT_OFFSET = { x = 0.0, y = 0.7, z = 0.0 }
local NO_ROTATION = { x = 0.0, y = 0.0, z = 0.0 }

local function dragSettings()
    local cfg = Config.drag or {}
    return cfg.offset or { x = 0.0, y = 0.5, z = 0.0 }, cfg.rotation or NO_ROTATION, tonumber(cfg.bone) or 0
end

local function attachTo(otherServerId, offset, rotation, bone)
    local otherPlayer = GetPlayerFromServerId(otherServerId)
    if otherPlayer == -1 then return false end
    local otherPed = GetPlayerPed(otherPlayer)
    if not otherPed or otherPed == 0 then return false end
    local myPed = PlayerPedId()
    rotation = rotation or NO_ROTATION
    AttachEntityToEntity(myPed, otherPed, bone or 0, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, false, false, false, false, 2, true)
    return true
end

local function detach()
    local myPed = PlayerPedId()
    if IsEntityAttached(myPed) then DetachEntity(myPed, true, true) end
end

RegisterNetEvent('qbpolice:client:escortStart', function(officerServerId)
    Police.escortOfficer = officerServerId
    attachTo(officerServerId, ESCORT_OFFSET)
end)
RegisterNetEvent('qbpolice:client:escortStop', function()
    Police.escortOfficer = nil
    detach()
end)

RegisterNetEvent('qbpolice:client:escortStartSelf', function(targetServerId)
    Police.escortedTarget = targetServerId
end)
RegisterNetEvent('qbpolice:client:escortStopSelf', function()
    Police.escortedTarget = nil
end)

-- The escorted player is attached just behind the officer, so relying only on
-- a target option makes the stop action difficult to aim at. `/escort` is a
-- toggle: use it again while escorting to release the current suspect.
local function closestPlayerServerId(maxDistance)
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local closest, closestDistance = nil, maxDistance or Config.cuff.distance

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if ped and ped ~= 0 then
                local distance = #(GetEntityCoords(ped) - myCoords)
                if distance <= closestDistance then
                    closest, closestDistance = GetPlayerServerId(player), distance
                end
            end
        end
    end

    return closest
end

Police.closestPlayerServerId = closestPlayerServerId

RegisterCommand('escort', function()
    if not Police.isOnDuty() then
        Police.notify('You must be on duty to escort a player.', 'error')
        return
    end

    if Police.escortedTarget then
        TriggerServerEvent('qbpolice:server:deEscort', Police.escortedTarget)
        return
    end

    if Police.draggedTarget then
        TriggerServerEvent('qbpolice:server:stopDrag', Police.draggedTarget)
        return
    end

    local target = closestPlayerServerId()
    if not target then
        Police.notify('No player nearby.', 'error')
        return
    end
    TriggerServerEvent('qbpolice:server:escort', target)
end, false)

-- The dragger's ped may not be streamed in on this client yet when the server
-- relays dragStart, so retry the attach for a few seconds instead of silently
-- leaving the dragged player unattached.
-- Release the player being dragged without having to aim the target eye at
-- them (they are attached right in front of the dragger). Command and default
-- key come from Config.drag; players can rebind the key in their settings.
local function releaseDrag()
    if not Police.draggedTarget then
        Police.notify('You are not dragging anyone.', 'error')
        return
    end
    TriggerServerEvent('qbpolice:server:stopDrag', Police.draggedTarget)
end

do
    local cfg = Config.drag or {}
    local command = cfg.releaseCommand
    if type(command) == 'string' and command ~= '' then
        RegisterCommand(command, releaseDrag, false)
        if type(cfg.releaseKey) == 'string' and cfg.releaseKey ~= '' then
            RegisterKeyMapping(command, 'Release dragged player', 'keyboard', cfg.releaseKey)
        end
    end
end

RegisterNetEvent('qbpolice:client:dragStart', function(draggerServerId)
    Police.dragger = draggerServerId
    local offset, rotation, bone = dragSettings()
    if attachTo(draggerServerId, offset, rotation, bone) then return end
    CreateThread(function()
        for _ = 1, 10 do
            Wait(500)
            if Police.dragger ~= draggerServerId then return end
            if attachTo(draggerServerId, offset, rotation, bone) then return end
        end
    end)
end)
RegisterNetEvent('qbpolice:client:dragStop', function()
    Police.dragger = nil
    detach()
end)

RegisterNetEvent('qbpolice:client:dragStartSelf', function(targetServerId)
    Police.draggedTarget = targetServerId
end)
RegisterNetEvent('qbpolice:client:dragStopSelf', function()
    Police.draggedTarget = nil
end)

local function registerEscortTargets()
    Police.target.reset('escort')
    Police.target.global('escort', 'player', {
        {
            label = 'Escort',
            icon = 'footprints',
            canInteract = function(entity)
                return Police.isOnDuty() and IsPedCuffed(entity) and not Police.escortedTarget
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:escort', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
        {
            label = 'Stop Escorting',
            icon = 'footprints',
            canInteract = function(entity)
                return Police.escortedTarget ~= nil and GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)) == Police.escortedTarget
            end,
            onSelect = function()
                TriggerServerEvent('qbpolice:server:deEscort', Police.escortedTarget)
            end,
        },
        {
            label = 'Drag',
            icon = 'move',
            canInteract = function(entity)
                return not Police.draggedTarget and GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)) ~= nil
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:startDrag', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
        {
            -- Shown on any nearby player while dragging: the dragged ped is
            -- attached and hard to aim at, and the server only accepts the
            -- stop from the dragger or the dragged player.
            label = 'Release',
            icon = 'hand',
            canInteract = function()
                return Police.draggedTarget ~= nil
            end,
            onSelect = function()
                TriggerServerEvent('qbpolice:server:stopDrag', Police.draggedTarget)
            end,
        },
    }, Config.cuff.distance)
end
registerEscortTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerEscortTargets() end
end)
