-- Door-breach minigame (new differentiator -- neither qb-policejob nor
-- qbx_police has one). Doors are registered with FiveM's own door system,
-- which self-replicates lock state across clients with no server round
-- trip; Kora.minigames.play('lockpick', ...) gates whether THIS client is
-- allowed to flip that state right now.

CreateThread(function()
    for _, door in ipairs(Config.breach.doors) do
        if door.enabled == false then goto continue end
        local doorHash = joaat(door.id)
        AddDoorToSystem(doorHash, joaat(door.model), door.coords.x, door.coords.y, door.coords.z, false, false, false)
        DoorSystemSetDoorState(doorHash, 1, false, false)  -- locked
        door.hash = doorHash
        ::continue::
    end
end)

local function attemptBreach(door)
    local result = Kora.minigames.play(Config.minigames.breach.type, Config.minigames.breach.opts)
    if not (result and result.success) then
        Police.notify(Kora.lang('Notify.breach_failed'), 'error')
        return
    end

    DoorSystemSetDoorState(door.hash, 0, false, false)  -- unlocked
    Police.notify(Kora.lang('Notify.door_breached'), 'success')
    SetTimeout(door.unlockedFor or 30000, function()
        DoorSystemSetDoorState(door.hash, 1, false, false)
    end)
end

local function registerBreachDoorTargets()
    Police.target.reset('breachDoors')
    for _, door in ipairs(Config.breach.doors) do
        if door.enabled == false then goto continue end
        Police.target.box('breachDoors', {
            coords = door.coords,
            size = { x = 1.2, y = 1.2, z = 2.2 },
            distance = 2.0,
            options = {
                {
                    label = Kora.lang('Menu.breach_door'),
                    icon = 'door-open',
                    canInteract = function()
                        return Police.isOnDuty()
                    end,
                    onSelect = function()
                        attemptBreach(door)
                    end,
                },
            },
        })
        ::continue::
    end
end

CreateThread(registerBreachDoorTargets)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerBreachDoorTargets() end
end)
