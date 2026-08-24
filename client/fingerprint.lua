-- Reveal a suspect's fingerprint id via search.

exports.qbtarget:addGlobalType('player', {
    options = {
        {
            label = 'Check Fingerprint',
            icon = 'fingerprint',
            canInteract = function(entity)
                return Police.isOnDuty() and IsPedCuffed(entity)
            end,
            onSelect = function(entity)
                local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local fingerprint = QB.callback.trigger('qbpolice:server:getFingerprint', targetServerId)
                if fingerprint then Police.notify(('Fingerprint: %s'):format(fingerprint), 'info') end
            end,
        },
    },
}, Config.cuff.distance)

RegisterNetEvent('police:client:showFingerprint', function(fingerprint)
    Police.notify(('Fingerprint: %s'):format(fingerprint), 'info')
end)
RegisterNetEvent('police:client:showFingerprintId', function(fingerprint)
    Police.notify(('Fingerprint: %s'):format(fingerprint), 'info')
end)
