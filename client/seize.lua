-- SeizeCash / SeizeDriverLicense targeting on a restrained suspect.

local function registerSeizeTargets()
    Police.target.reset('seize')
    Police.target.global('seize', 'player', {
        {
            label = 'Seize Cash',
            icon = 'banknote',
            canInteract = function(entity)
                return Police.isOnDuty() and Police.isPedCuffed(entity)
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:seizeCash', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
        {
            label = "Seize Driver's License",
            icon = 'id-card',
            canInteract = function(entity)
                return Police.isOnDuty() and Police.isPedCuffed(entity)
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:seizeDriverLicense', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
    }, Config.cuff.distance)
end
registerSeizeTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerSeizeTargets() end
end)
