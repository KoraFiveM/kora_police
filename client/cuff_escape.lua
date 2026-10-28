-- Ported qbx_police-style cuff-escape skillcheck: a soft-cuffed suspect can
-- attempt to break free. Per-attempt difficulty comes from
-- Config.cuff.breakCuffsDifficulty ('medium'/'hard'/'medium' in qbx_police);
-- QB.minigames has no notion of named "difficulty" presets of its own, so
-- each name is mapped onto concrete trusted options by the server before it
-- issues a kora_lib proof authorization.

local attempting = false

local function attemptBreak()
    if attempting or not Police.cuffed or not Police.soft then return end
    attempting = true

    local authorization, beginErr = QB.callback.trigger('qbpolice:server:beginBreakCuffs')
    if not authorization then
        attempting = false
        Police.notify(beginErr or 'You cannot try to escape yet.', 'error')
        return
    end

    local result = QB.minigames.play(Config.minigames.breakCuffs.type, nil, authorization)
    attempting = false

    if result and result.success then
        Police.breakCuffAttempts = 0
        TriggerServerEvent('qbpolice:server:breakCuffsResult', result.proof)
    else
        if not (result and result.cancelled) then Police.notify('You failed to break free.', 'error') end
        TriggerServerEvent('qbpolice:server:breakCuffsResult', false)
    end
end

RegisterCommand('breakcuffs', function()
    attemptBreak()
end, false)

AddEventHandler('qbpolice:client:cuffStateChanged', function(cuffed, soft)
    if not (cuffed and soft) then Police.breakCuffAttempts = 0 end
end)
