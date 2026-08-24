-- Dispatch fan-out is entirely qbcore's Core.dispatch.alert (exports.qbcore:alert)
-- -- this file only defaults `jobs = {'police'}` for callers within this
-- resource and pushes the legacy on-duty cop-count broadcast
-- (`UpdateCurrentCops`/`SetCopCount`) whenever a police officer's duty state
-- changes. The legacy `police:server:policeAlert`/`police:client:policeAlert`
-- events fire automatically from `exports.qbcore:alert` itself (gated by
-- `Config.dispatch.legacyEvents` in qbcore) -- nothing here re-fires them.

---@param payload table {title?, message?, coords?, code?, blip?, sound?, radius?, data?, jobs?}
---@return integer recipientCount
function Police.dispatch(payload)
    payload = payload or {}
    payload.jobs = payload.jobs or { Config.police.job }
    payload.radius = payload.radius or Config.dispatch.robberyRadius
    return exports.qbcore:alert(payload)
end

local function broadcastCopCount()
    local count = exports.qbcore:getDutyCount(Config.police.job)
    local recipients = exports.qbcore:getPlayersByJob(Config.police.job, true)
    for _, src in ipairs(recipients) do
        TriggerClientEvent('qbpolice:client:updateCopCount', src, count)
        -- Legacy names, both fired so either style of listener keeps working.
        TriggerClientEvent('police:client:UpdateCurrentCops', src, count)
        TriggerClientEvent('police:client:SetCopCount', src, count)
    end
end
Police.broadcastCopCount = broadcastCopCount

AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty)
    local job = Police.job(src)
    if job and job.name == Config.police.job then broadcastCopCount() end
end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
    if job and job.name == Config.police.job then broadcastCopCount() end
end)
AddEventHandler('playerDropped', function()
    local job = Police.job(source)
    if job and job.name == Config.police.job then broadcastCopCount() end
end)

-- Officer-requested backup. Anything else that wants a police dispatch
-- (qbdrugs' copAlerts, a robbery script, ...) should call
-- `exports.qbcore:alert({jobs={'police'}, ...})` directly rather than this
-- net event, which only exists for the calling PLAYER's own client request.
RegisterNetEvent('qbpolice:server:requestBackup', function(payload)
    if not Police.isPolice(source) then return end
    payload = type(payload) == 'table' and payload or {}
    payload.title = payload.title or 'Backup Requested'
    Police.dispatch(payload)
end)
