-- Escort (suspect walks alongside/behind the officer) and drag (kidnap-style,
-- for an unconscious/uncooperative target). Not solvable with
-- Kora.anim.attachProp -- the other player owns their own networked ped, so
-- each side's OWN client issues AttachEntityToEntity on itself, driven by a
-- server relay rather than kora_police trying to move another player's entity
-- remotely. The officer's client only renders local UI state; it never
-- attaches anything on the suspect's behalf.

local ESCORT_OFFSET = { x = 0.0, y = 0.7, z = 0.0 }
local DRAG_OFFSET = { x = 0.0, y = 0.5, z = 0.0 }

local function attachTo(otherServerId, offset)
    local otherPlayer = GetPlayerFromServerId(otherServerId)
    if otherPlayer == -1 then return end
    local otherPed = GetPlayerPed(otherPlayer)
    if not otherPed or otherPed == 0 then return end
    local myPed = PlayerPedId()
    AttachEntityToEntity(myPed, otherPed, 0, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
end

local function detach()
    local myPed = PlayerPedId()
    if IsEntityAttached(myPed) then DetachEntity(myPed, true, true) end
end

-- Escorted side ----------------------------------------------------------

RegisterNetEvent('qbpolice:client:escortStart', function(officerServerId)
    Police.escortOfficer = officerServerId
    attachTo(officerServerId, ESCORT_OFFSET)
end)
RegisterNetEvent('qbpolice:client:escortStop', function()
    Police.escortOfficer = nil
    detach()
end)

-- Officer side (escorting) ------------------------------------------------

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

    local target = closestPlayerServerId()
    if not target then
        Police.notify('No player nearby.', 'error')
        return
    end
    TriggerServerEvent('qbpolice:server:escort', target)
end, false)

-- Dragged side --------------------------------------------------------

RegisterNetEvent('qbpolice:client:dragStart', function(draggerServerId)
    Police.dragger = draggerServerId
    attachTo(draggerServerId, DRAG_OFFSET)
end)
RegisterNetEvent('qbpolice:client:dragStop', function()
    Police.dragger = nil
    detach()
end)

-- Dragger side --------------------------------------------------------

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
            label = 'Stop Dragging',
            icon = 'move',
            canInteract = function(entity)
                return Police.draggedTarget ~= nil and GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)) == Police.draggedTarget
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
