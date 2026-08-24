-- Legacy RobPlayer -- plain player-vs-player, no cuff requirement.

local function registerRobTargets()
    exports.qbtarget:addGlobalType('player', {
        {
            label = 'Rob',
            icon = 'hand-coins',
            canInteract = function()
                return not Police.isOnDuty()
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:rob', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
    }, Config.cuff.distance)
end
registerRobTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qbtarget' then registerRobTargets() end
end)
