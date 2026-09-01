-- Police calls are raised through qbdispatch, which owns the call lifecycle and
-- every bit of presentation. This file only supplies the police-specific parts:
-- what counts as a police matter, and how each incident is worded.
--
-- exports.qbcore:alert is deliberately still reachable for third-party scripts
-- written against the older fan-out -- qbdispatch mirrors it -- but nothing here
-- goes through it any more.

-- src -> GetGameTimer() of that officer's last panic alarm. Server-side because
-- a client-side cooldown is a suggestion: the net event is reachable directly.
--
-- Declared at the top because the lifecycle handlers below clear it; a `local`
-- further down would leave those reading an undeclared GLOBAL instead, which is
-- nil and errors on index.
local lastPanicAt = {}

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

    return exports.qbdispatch:createCall(payload)
end

local function broadcastCopCount()
    local count = exports.qbcore:getDutyCountByType(Config.police.jobType)
    for _, src in ipairs(exports.qbcore:getPlayersByJobType(Config.police.jobType, true)) do
        TriggerClientEvent('qbpolice:client:updateCopCount', src, count)
        -- Legacy names, both fired so either style of listener keeps working.
        TriggerClientEvent('police:client:UpdateCurrentCops', src, count)
        TriggerClientEvent('police:client:SetCopCount', src, count)
    end
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
    for _, unit in ipairs(exports.qbcore:getOnDutyRoster({ jobType = Config.police.jobType })) do
        if unit.src == src then
            return unit.callsign or unit.name or ('Unit %d'):format(src)
        end
    end
    return ('Unit %d'):format(src)
end

-- Officer-requested backup. Only for the calling PLAYER's own request; anything
-- else wanting a police call (a robbery script, a drug lab) calls
-- exports.qbdispatch:createCall directly.
RegisterNetEvent('qbpolice:server:requestBackup', function(payload)
    local src = source
    if not Police.isLeo(src) then return end

    payload = type(payload) == 'table' and payload or {}

    Police.dispatch({
        code = '10-78',
        title = 'Backup Requested',
        message = payload.message or ('%s is requesting backup.'):format(officerName(src)),
        priority = payload.priority or 2,
        coords = payload.coords,
        icon = 'radio',
        data = { officer = officerName(src) },
    })
end)

-- The panic button: officer down.
--
-- TWO calls, deliberately. Police and EMS are separate services with separate
-- feeds, separate histories and separate wording -- an officer needs backup, a
-- paramedic needs a patient location. Bundling them into one "emergency" call
-- would give both services a shared feed neither could clear independently,
-- which is exactly why qbdispatch refuses a multi-service call.
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
        QB.notify.send(src, {
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

    exports.qbdispatch:createCall({
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
RegisterNetEvent('qbpolice:server:crimeDetected', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end

    -- Coordinates are read server-side from the reporting player's own ped, not
    -- taken from the payload: a modified client could otherwise put a fake
    -- shots-fired call anywhere on the map.
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)

    Police.dispatch({
        code = payload.code,
        title = payload.title,
        message = payload.message,
        priority = payload.priority,
        icon = payload.icon,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        data = type(payload.data) == 'table' and payload.data or nil,
    })
end)
