-- Legacy RobPlayer -- plain player-vs-player, no cuff requirement.

exports.qbtarget:addGlobalType('player', {
    options = {
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
    },
}, Config.cuff.distance)
