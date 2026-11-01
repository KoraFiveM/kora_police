-- Police calls are raised through kora_dispatch, which owns the call lifecycle and
-- every bit of presentation. This file only supplies the police-specific parts:
-- what counts as a police matter, and how each incident is worded.
--
-- exports.kora_core:alert is deliberately still reachable for third-party scripts
-- written against the older fan-out -- kora_dispatch mirrors it -- but nothing here
-- goes through it any more.

-- src -> GetGameTimer() of that officer's last panic alarm. Server-side because
-- a client-side cooldown is a suggestion: the net event is reachable directly.
--
-- Declared at the top because the lifecycle handlers below clear it; a `local`
-- further down would leave those reading an undeclared GLOBAL instead, which is
-- nil and errors on index.
local lastPanicAt = {}

local playerAlerts = {
    ['qbpolice:backup'] = {
        jobTypes = { Config.police.jobType }, code = '10-78', title = 'Backup Requested',
        message = 'An on-duty officer is requesting backup.', priority = 2, icon = 'radio',
        cooldown = Config.dispatch.backupCooldown,
        requiredJobType = Config.police.jobType,
    },
    ['qbpolice:gunfire'] = {
        jobTypes = { Config.police.jobType }, code = '10-31', title = 'Shots Fired',
        message = 'Gunfire was reported nearby.', priority = 1, icon = 'crosshair',
        cooldown = Config.dispatch.shotsFiredCooldown,
    },
    ['qbpolice:gunfire:suppressed'] = {
        jobTypes = { Config.police.jobType }, code = '10-31', title = 'Suppressed Gunfire',
        message = 'Possible suppressed gunfire was reported nearby.', priority = 2, icon = 'crosshair',
        cooldown = Config.dispatch.shotsFiredCooldown,
    },
    ['qbpolice:vehicle-theft'] = {
        jobTypes = { Config.police.jobType }, code = '10-16', title = 'Vehicle Theft',
        message = 'A vehicle theft was reported nearby.', priority = 2, icon = 'car',
        cooldown = Config.dispatch.vehicleTheftCooldown,
    },
    ['qbpolice:melee'] = {
        jobTypes = { Config.police.jobType }, code = '10-10', title = 'Fight in Progress',
        message = 'A fight was reported nearby.', priority = 3, icon = 'person',
        cooldown = Config.dispatch.meleeCooldown,
    },
}

for key, definition in pairs(playerAlerts) do
    local ok, err = exports.kora_dispatch:registerPlayerAlert(key, definition)
    if not ok then print(('^3[qbpolice]^7 could not register dispatch alert %s: %s'):format(key, err)) end
end

---Raises a law-enforcement call. Defaults target the whole LEO service (police,
---sheriff, state troopers -- whatever this server has registered with
---`type = 'leo'`), not just this resource's own job name.
---@param payload table
---@return integer|false callId, integer|string recipientCountOrError
function Police.dispatch(payload)
    payload = payload or {}
    if not payload.jobs and not payload.jobTypes then
        payload.jobTypes = { Config.police.jobType }
    end
    payload.radius = payload.radius or Config.dispatch.robberyRadius

    return exports.kora_dispatch:createCall(payload)
end

local function broadcastCopCount()
    local count = exports.kora_core:getDutyCountByType(Config.police.jobType)
    for _, src in ipairs(exports.kora_core:getPlayersByJobType(Config.police.jobType, true)) do
        TriggerClientEvent('qbpolice:client:updateCopCount', src, count)
        -- Legacy names, both fired so either style of listener keeps working.
        TriggerClientEvent('police:client:UpdateCurrentCops', src, count)
        TriggerClientEvent('police:client:SetCopCount', src, count)
    end
    -- Stock qb-policejob broadcasts the bare count to EVERY client as
    -- `police:SetCopCount` (heist/robbery scripts read it); the count is not secret.
    TriggerClientEvent('police:SetCopCount', -1, count)
end
Police.broadcastCopCount = broadcastCopCount

AddEventHandler('QBCore:Server:SetDuty', function(src)
    local job = Police.job(src)
    if job and job.type == Config.police.jobType then broadcastCopCount() end
end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(_, job)
    if job and job.type == Config.police.jobType then broadcastCopCount() end
end)
AddEventHandler('playerDropped', function()
    local job = Police.job(source)
    lastPanicAt[source] = nil
    if job and job.type == Config.police.jobType then broadcastCopCount() end
end)

-- Going off duty ends the shift the alarm belonged to. Coming back on and
-- immediately needing help is a new emergency, not a repeat of the old one.
AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty)
    if not onDuty then lastPanicAt[src] = nil end
end)

---Whether a source is on-duty law enforcement, by job TYPE.
---
---Police.isPolice gates on the job NAME, which is right for department-specific
---things (this force's armory, its evidence lockers). It is wrong for dispatch:
---calls target the whole LEO service, so a sheriff already RECEIVES them --
---without this they could be alerted to an officer down but not raise their own
---panic alarm or request backup.
---@param src integer
---@return boolean
function Police.isLeo(src)
    local job = Police.job(src)
    return job ~= nil and job.type == Config.police.jobType and job.onduty == true
end

---Names an officer the way dispatch should read them out: callsign first,
---falling back to a surname, and only then to a bare source id.
---@param src integer
---@return string
local function officerName(src)
    for _, unit in ipairs(exports.kora_core:getOnDutyRoster({ jobType = Config.police.jobType })) do
        if unit.src == src then
            return unit.callsign or unit.name or ('Unit %d'):format(src)
        end
    end
    return ('Unit %d'):format(src)
end

-- Officer-requested backup. Only for the calling PLAYER's own request; anything
-- else wanting a police call (a robbery script, a drug lab) calls
-- exports.kora_dispatch:createCall directly.
Kora.events.register('qbpolice:server:requestBackup', function(src)
    if not Police.isLeo(src) then return end

    local callId, reason, remaining = exports.kora_dispatch:createPlayerCall(src, 'qbpolice:backup')
    if not callId then
        Kora.notify.send(src, {
            message = remaining
                and ('A backup request is already active (%ds).'):format(math.ceil(remaining / 1000))
                or ('Dispatch could not create the call: %s.'):format(reason or 'unknown error'),
            type = 'error',
        })
    end
end, { rateLimit = { max = 2, window = 5000 } })

-- The panic button: officer down.
--
-- TWO calls, deliberately. Police and EMS are separate services with separate
-- feeds, separate histories and separate wording -- an officer needs backup, a
-- paramedic needs a patient location. Bundling them into one "emergency" call
-- would give both services a shared feed neither could clear independently,
-- which is exactly why kora_dispatch refuses a multi-service call.
---@param src integer
---@return boolean elapsed
---@return integer remainingMs
function Police.panicCooldownElapsed(src)
    local last = lastPanicAt[src]
    if not last then return true, 0 end

    local remaining = Config.dispatch.panicCooldown - (GetGameTimer() - last)
    if remaining <= 0 then return true, 0 end
    return false, remaining
end

---Test seam and duty hook: forgets an officer's cooldown.
---@param src integer
function Police.clearPanicCooldown(src)
    lastPanicAt[src] = nil
end

RegisterNetEvent('qbpolice:server:panic', function()
    local src = source
    if not Police.isLeo(src) then return end

    -- One press raises TWO calls, so a mashed key doubles up in both services'
    -- feeds. The officer is told their alarm is already out rather than being
    -- silently ignored -- somebody pressing this is having the worst moment of
    -- their shift and needs to know it was heard.
    local elapsed, remaining = Police.panicCooldownElapsed(src)
    if not elapsed then
        Kora.notify.send(src, {
            message = ('Your panic alarm is already active (%ds).'):format(math.ceil(remaining / 1000)),
            type = 'error',
        })
        return
    end
    lastPanicAt[src] = GetGameTimer()

    local name = officerName(src)

    -- Position is read server-side from the officer's own ped rather than taken
    -- from the client, same rule as the detector path below: a panic alarm that
    -- can be fired at arbitrary coordinates is a way to pull every unit on the
    -- server to a spot of the caller's choosing.
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local position = GetEntityCoords(ped)
    local coords = { x = position.x, y = position.y, z = position.z }

    Police.dispatch({
        code = '10-99',
        title = 'Officer Down',
        message = ('%s has activated their panic alarm. All units respond.'):format(name),
        priority = 1,
        coords = coords,
        icon = 'siren',
        data = { officer = name },
    })

    exports.kora_dispatch:createCall({
        jobTypes = { Config.police.emsJobType },
        code = '10-52',
        title = 'Officer Down',
        message = ('%s is down and needs medical assistance.'):format(name),
        priority = 1,
        coords = coords,
        icon = 'heart-pulse',
        data = { officer = name },
    })
end)

-- Client-side crime detectors (client/detectors.lua) report here. The client
-- decides WHEN, the server decides whether that player is allowed to generate a
-- call and what it may contain -- a client cannot hand over a priority, a
-- service, or anyone else's coordinates.
Kora.events.register('qbpolice:server:crimeDetected', function(src, incident)
    if playerAlerts[incident] == nil or incident == 'qbpolice:backup' then return end
    exports.kora_dispatch:createPlayerCall(src, incident)
end, { rateLimit = { max = 8, window = 5000 } })
