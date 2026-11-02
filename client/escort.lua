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
    DetachEntity(PlayerPedId(), true, true)
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

-- Release the player being dragged without having to aim the target eye at
-- them (they are attached right in front of the dragger). Command and default
-- key come from Config.drag; players can rebind the key in their settings.
-- The key is a kora_lib keybind that is only enabled while this player drags
-- someone, so E (also the door, target and door-creator key) does nothing here
-- otherwise, and release is silent when nothing is being dragged.
local lastReleaseAt = 0

local function targetingActive()
    local ok, state = pcall(function() return exports.kora_target:getState() end)
    return ok and type(state) == 'table' and state.active == true
end

local function releaseDrag()
    if not Police.draggedTarget then return end
    local now = GetGameTimer()
    if now - lastReleaseAt < 750 then return end
    lastReleaseAt = now
    TriggerServerEvent('qbpolice:server:stopDrag', Police.draggedTarget)
end

local releaseBinding

do
    local cfg = Config.drag or {}
    local command = cfg.releaseCommand
    if type(command) == 'string' and command ~= '' then
        RegisterCommand(command, function()
            if targetingActive() then return end
            releaseDrag()
        end, false)
    end
    if type(cfg.releaseKey) == 'string' and cfg.releaseKey ~= '' then
        releaseBinding = Kora.keybind.add({
            name = 'kora_police_releasedrag',
            description = 'Police: release dragged player',
            defaultKey = cfg.releaseKey,
            disabled = true,
            onPressed = function()
                if not targetingActive() then releaseDrag() end
            end,
        })
    end
end

local function setReleaseKeyActive(active)
    if releaseBinding then releaseBinding.disable(not active) end
end

-- Optional fallback, off by default (Config.drag.releaseControl = 0): poll a
-- raw control every frame, only while dragging, for servers where another
-- script swallows the release key.
local releasePollRunning = false

local function startReleasePoll()
    local control = tonumber((Config.drag or {}).releaseControl)
    if releasePollRunning or not control or control <= 0 then return end
    releasePollRunning = true
    CreateThread(function()
        while Police.draggedTarget do
            if IsControlJustPressed(0, control) and not targetingActive() then releaseDrag() end
            Wait(0)
        end
        releasePollRunning = false
    end)
end

-- The dragger's ped may not be streamed in on this client yet when the server
-- relays dragStart, so retry the attach for a few seconds instead of silently
-- leaving the dragged player unattached.
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
    if (Config.drag or {}).releaseHint ~= false then
        Police.notify('Dragging a player. Release with /' .. tostring((Config.drag or {}).releaseCommand or 'releasedrag') .. ' or the Release option.', 'info')
    end
    setReleaseKeyActive(true)
    startReleasePoll()
end)
RegisterNetEvent('qbpolice:client:dragStopSelf', function()
    Police.draggedTarget = nil
    setReleaseKeyActive(false)
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
    }, Config.cuff.distance)

    -- The dragged ped is attached to the dragger and the raycast ignores the
    -- dragger's own ped, so offer Release on whatever is aimed at (players,
    -- other peds, vehicles) rather than only on the attached ped.
    for _, entityType in ipairs({ 'player', 'ped', 'vehicle' }) do
        Police.target.global('escort', entityType, {
            {
                label = 'Release',
                icon = 'hand',
                canInteract = function()
                    return Police.draggedTarget ~= nil
                end,
                onSelect = releaseDrag,
            },
        }, Config.cuff.distance)
    end
end
registerEscortTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerEscortTargets() end
end)
