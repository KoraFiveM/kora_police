-- Reveal a suspect's fingerprint id via search.

local function registerFingerprintTargets()
    Police.target.reset('fingerprint')
    Police.target.global('fingerprint', 'player', {
        {
            label = Kora.lang('Menu.check_fingerprint'),
            icon = 'fingerprint',
            canInteract = function(entity)
                return Police.isOnDuty() and Police.isPedCuffed(entity)
            end,
            onSelect = function(entity)
                local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local fingerprint = Kora.callback.trigger('kora_police:server:getFingerprint', targetServerId)
                if fingerprint then Police.notify((Kora.lang('Notify.fingerprint')):format(fingerprint), 'info') end
            end,
        },
    }, Config.cuff.distance)
end
registerFingerprintTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerFingerprintTargets() end
end)

RegisterNetEvent('police:client:showFingerprint', function(fingerprint)
    Police.notify((Kora.lang('Notify.fingerprint')):format(fingerprint), 'info')
end)
RegisterNetEvent('police:client:showFingerprintId', function(fingerprint)
    Police.notify((Kora.lang('Notify.fingerprint')):format(fingerprint), 'info')
end)
