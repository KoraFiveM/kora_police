-- Ported qbx_police-style cuff-escape skillcheck: a soft-cuffed suspect can
-- attempt to break free. Per-attempt difficulty comes from
-- Config.cuff.breakCuffsDifficulty ('medium'/'hard'/'medium' in qbx_police);
-- QB.minigames has no notion of named "difficulty" presets of its own, so
-- each name is mapped onto a concrete `mash` opts table here.

local DIFFICULTY_OPTS = {
    easy = { requiredPresses = 12, timeLimit = 8000 },
    medium = { requiredPresses = 20, timeLimit = 7000 },
    hard = { requiredPresses = 30, timeLimit = 6000 },
}

local attempting = false

local function attemptBreak()
    if attempting or not Police.cuffed or not Police.soft then return end
    attempting = true

    local attemptIndex = (Police.breakCuffAttempts or 0) + 1
    Police.breakCuffAttempts = attemptIndex
    local difficultyName = Config.cuff.breakCuffsDifficulty[math.min(attemptIndex, #Config.cuff.breakCuffsDifficulty)]
    local opts = DIFFICULTY_OPTS[difficultyName] or DIFFICULTY_OPTS.medium

    local result = QB.minigames.play(Config.minigames.breakCuffs.type, opts)
    attempting = false

    if result and result.success then
        Police.notify('You broke free!', 'success')
        Police.breakCuffAttempts = 0
        TriggerServerEvent('qbpolice:server:breakCuffsResult', true)
    elseif not (result and result.cancelled) then
        Police.notify('You failed to break free.', 'error')
        TriggerServerEvent('qbpolice:server:breakCuffsResult', false)
    end
end

RegisterCommand('breakcuffs', function()
    attemptBreak()
end, false)

AddEventHandler('qbpolice:client:cuffStateChanged', function(cuffed, soft)
    if not (cuffed and soft) then Police.breakCuffAttempts = 0 end
end)
