-- Legacy RobPlayer -- plain player-vs-player, no cuff requirement.

-- The server validated the rob and granted inventory access; open the
-- target's inventory as the secondary inventory (kora_inventory re-checks the
-- grant server-side, so a forged event here opens nothing).
RegisterNetEvent('kora_police:client:openRob', function(targetServerId)
    exports.kora_inventory:openInventory('player', targetServerId)
end)

local function registerRobTargets()
    Police.target.reset('rob')
    Police.target.global('rob', 'player', {
        {
            label = 'Rob',
            icon = 'hand-coins',
            canInteract = function(entity)
                return not Police.isOnDuty() and Police.isPedRestrained(entity)
            end,
            onSelect = function(entity)
                TriggerServerEvent('kora_police:server:rob', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
    }, Config.cuff.distance)
end
registerRobTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerRobTargets() end
end)
