-- Citations. Officer enters an amount/reason via QB.nui.openInputDialog; the
-- server is authoritative on whether the target can actually be charged.

exports.qbtarget:addGlobalType('player', {
    options = {
        {
            label = 'Issue Citation',
            icon = 'receipt',
            canInteract = function()
                return Police.isOnDuty()
            end,
            onSelect = function(entity)
                local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local result = QB.nui.openInputDialog({
                    { id = 'amount', label = 'Fine Amount', type = 'number', default = Config.fine.tiers[1][1], min = 1, required = true },
                    { id = 'reason', label = 'Reason', type = 'text' },
                }, 'Issue Citation')
                if not result or not result.values then return end
                TriggerServerEvent('qbpolice:server:bill', targetServerId, result.values.amount, result.values.reason)
            end,
        },
    },
}, Config.cuff.distance)
