-- Shared client-side state. Bare global table, same cross-file convention as
-- the server realm's Police table (and qbadmin's own Admin table).

Police = Police or {}
Police.cuffed = false
Police.soft = false
Police.escortOfficer = nil     -- src of the officer escorting me, if any
Police.escortedTarget = nil    -- src of the suspect I'm escorting, if any
Police.dragger = nil           -- src of the player dragging me, if any
Police.draggedTarget = nil     -- src of the player I'm dragging, if any

function Police.isOnDuty()
    local job = exports.qbcore:getPlayerData({ 'job' })
    return job ~= nil and job.name == Config.police.job and job.onduty == true
end

function Police.myGradeLevel()
    local job = exports.qbcore:getPlayerData({ 'job' })
    if not job or job.name ~= Config.police.job then return -1 end
    return tonumber(job.grade and job.grade.level) or 0
end

function Police.notify(message, type_)
    QB.notify.send({ message = message, type = type_ or 'info' })
end

RegisterNetEvent('qbpolice:client:cuffed', function(cuffed, soft, otherSrc)
    Police.cuffed = cuffed == true
    Police.soft = soft == true
    TriggerEvent('qbpolice:client:cuffStateChanged', Police.cuffed, Police.soft, otherSrc)
end)

---Legacy client export.
function IsHandcuffed()
    return Police.cuffed
end
exports('IsHandcuffed', IsHandcuffed)
