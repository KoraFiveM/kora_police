-- SeizeCash / SeizeDriverLicense targeting on a restrained suspect.

exports.qbtarget:addGlobalType('player', {
    options = {
        {
            label = 'Seize Cash',
            icon = 'banknote',
            canInteract = function(entity)
                return Police.isOnDuty() and IsPedCuffed(entity)
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:seizeCash', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
        {
            label = "Seize Driver's License",
            icon = 'id-card',
            canInteract = function(entity)
                return Police.isOnDuty() and IsPedCuffed(entity)
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:seizeDriverLicense', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
    },
}, Config.cuff.distance)
