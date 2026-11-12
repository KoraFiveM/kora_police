-- Dispatch presentation now belongs entirely to kora_dispatch: the call feed, the
-- map, history, the response state machine and the route blip all live there.
--
-- What remains is the police-specific side: the officer-facing commands that
-- RAISE calls, and the cop-count listeners other police features read.

local function requestBackup()
    if not Police.isOnDuty() then
        return Police.notify(Kora.lang('Notify.on_duty_for_backup'), 'error')
    end

    Kora.events.trigger('kora_police:server:requestBackup')
end

RegisterCommand('backup', requestBackup, false)

-- The panic button. Real qb-policejob had one (police:client:SendPoliceEmergencyAlert)
-- and the new resource lost it entirely -- an officer down had no way to say so.
--
-- It raises TWO calls on purpose: one to law enforcement, one to EMS. They are
-- separate incidents with different wording, different priorities from each
-- service's point of view, and separate histories to clear -- which is exactly
-- why dispatch refuses to bundle services into a single call.
Kora.keybind.add({
    name = 'kora_police_panic',
    description = Kora.lang('Dispatch.panic_button'),
    defaultKey = Config.dispatch.panicKey,
    onPressed = function()
        if not Police.isOnDuty() then return end
        -- No coordinates sent: the server reads them from the officer's own
        -- ped, so a modified client cannot fire the alarm at a location of its
        -- choosing and pull every unit on the server there.
        TriggerServerEvent('kora_police:server:panic')
    end,
})

RegisterNetEvent('kora_police:client:updateCopCount', function(count)
    Police.copCount = count
end)
RegisterNetEvent('police:client:UpdateCurrentCops', function(count)
    Police.copCount = count
end)
RegisterNetEvent('police:SetCopCount', function(count)
    Police.copCount = count
end)
RegisterNetEvent('police:client:SetCopCount', function(count)
    Police.copCount = count
end)

-- Law enforcement blue. Client-side because it is per-player: an officer and a
-- paramedic on the same server see different accents at the same moment, so this
-- can never be a server setting.
CreateThread(function()
    Wait(1500) -- let kora_dispatch's own frame mount before pushing tokens at it
    exports.kora_dispatch:setTheme(Config.dispatch.accent)
end)
