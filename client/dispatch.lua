-- Dispatch presentation now belongs entirely to qbdispatch: the call feed, the
-- map, history, the response state machine and the route blip all live there.
--
-- What used to be here was a renderer -- two notifies and a routed blip on a
-- SetTimeout, with an activeBlips table that grew forever because entries were
-- never removed from it. All of that is gone rather than duplicated; a call
-- rendered twice, once by each system, is worse than one rendered well.
--
-- What remains is the police-specific side: the officer-facing commands that
-- RAISE calls, and the cop-count listeners other police features read.

local function requestBackup()
    if not Police.isOnDuty() then
        return Police.notify('You must be on duty to request backup.', 'error')
    end

    Kora.events.trigger('qbpolice:server:requestBackup')
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
    name = 'qbpolice_panic',
    description = 'Police: panic button (officer down)',
    defaultKey = Config.dispatch.panicKey,
    onPressed = function()
        if not Police.isOnDuty() then return end
        -- No coordinates sent: the server reads them from the officer's own
        -- ped, so a modified client cannot fire the alarm at a location of its
        -- choosing and pull every unit on the server there.
        TriggerServerEvent('qbpolice:server:panic')
    end,
})

RegisterNetEvent('qbpolice:client:updateCopCount', function(count)
    Police.copCount = count
end)
RegisterNetEvent('police:client:UpdateCurrentCops', function(count)
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
