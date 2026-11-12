-- Citations. Officer enters an amount/reason via Kora.nui.openInputDialog; the
-- server is authoritative on whether the target can actually be charged.

local function registerBillTargets()
    Police.target.reset('bill')
    Police.target.global('bill', 'player', {
        {
            label = Kora.lang('Menu.issue_citation'),
            icon = 'receipt',
            canInteract = function()
                return Police.isOnDuty()
            end,
            onSelect = function(entity)
                local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId <= 0 then
                    return Police.notify(Kora.lang('Notify.no_player_to_cite'), 'error')
                end
                local result = Kora.nui.openInputDialog({
                    { id = 'amount', label = Kora.lang('Menu.fine_amount'), type = 'number', default = Config.fine.tiers[1][1], min = 1, required = true },
                    { id = 'reason', label = Kora.lang('Menu.reason'), type = 'text' },
                }, Kora.lang('Menu.issue_citation'))
                if not result or not result.values then return end
                TriggerServerEvent('kora_police:server:bill', targetServerId, result.values.amount, result.values.reason)
            end,
        },
    }, Config.cuff.distance)
end
registerBillTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerBillTargets() end
end)
