-- Cuff-and-book: officer targets a cuffed suspect to send them to jail for
-- Config.jail.defaultMinutes. Server clears cuff/escort/drag state on booking.

local function registerJailTargets()
    Police.target.reset('jail')
    Police.target.global('jail', 'player', {
        {
            label = Kora.lang('Menu.book_jail'),
            icon = 'gavel',
            canInteract = function(entity)
                return Police.isOnDuty() and Police.isPedCuffed(entity)
            end,
            onSelect = function(entity)
                local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local result = Kora.nui.openInputDialog({
                    { id = 'minutes', label = Kora.lang('Menu.minutes'), type = 'number', default = Config.jail.defaultMinutes, min = 1, required = true },
                    { id = 'reason', label = Kora.lang('Menu.reason'), type = 'text' },
                }, 'Book Suspect')
                if not result or not result.values then return end
                TriggerServerEvent('kora_police:server:jailPlayer', targetServerId, result.values.minutes, result.values.reason)
            end,
        },
    }, Config.cuff.distance)
end
registerJailTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerJailTargets() end
end)
