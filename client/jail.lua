-- Cuff-and-book: officer targets a cuffed suspect to send them to jail for
-- Config.jail.defaultMinutes. Server clears cuff/escort/drag state on booking.

exports.qbtarget:addGlobalType('player', {
    options = {
        {
            label = 'Book (Jail)',
            icon = 'gavel',
            canInteract = function(entity)
                return Police.isOnDuty() and IsPedCuffed(entity)
            end,
            onSelect = function(entity)
                local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local result = QB.nui.openInputDialog({
                    { id = 'minutes', label = 'Minutes', type = 'number', default = Config.jail.defaultMinutes, min = 1, required = true },
                    { id = 'reason', label = 'Reason', type = 'text' },
                }, 'Book Suspect')
                if not result or not result.values then return end
                TriggerServerEvent('qbpolice:server:jailPlayer', targetServerId, result.values.minutes, result.values.reason)
            end,
        },
    },
}, Config.cuff.distance)
