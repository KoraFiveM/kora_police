-- Citations. Officer enters an amount/reason via QB.nui.openInputDialog; the
-- server is authoritative on whether the target can actually be charged.

local function registerBillTargets()
    Police.target.reset('bill')
    Police.target.global('bill', 'player', {
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
    }, Config.cuff.distance)
end
registerBillTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerBillTargets() end
end)
