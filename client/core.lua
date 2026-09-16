-- Shared client-side state. Bare global table, same cross-file convention as
-- the server realm's Police table (and qbadmin's own Admin table).

Police = Police or {}
Police.cuffed = false
Police.soft = false
Police.escortOfficer = nil     -- src of the officer escorting me, if any
Police.escortedTarget = nil    -- src of the suspect I'm escorting, if any
Police.dragger = nil           -- src of the player dragging me, if any
Police.draggedTarget = nil     -- src of the player I'm dragging, if any
Police.targetGroups = Police.targetGroups or {}
Police.target = Police.target or {}

local function removeTargetGroup(group)
    for _, registration in ipairs(Police.targetGroups[group] or {}) do
        registration.remove(registration.id)
    end
    Police.targetGroups[group] = {}
end

local function trackTarget(group, id, remove)
    local registrations = Police.targetGroups[group]
    assert(registrations, ('target group %s must be reset before registrations are added'):format(group))
    registrations[#registrations + 1] = { id = id, remove = remove }
    return id
end

---Replaces one feature's qbtarget registrations without stacking options.
---@param group string
function Police.target.reset(group)
    removeTargetGroup(group)
end

---@param group string
---@param entityType QBTargetGlobalType
---@param options QBTargetOption[]
---@param distance? number
---@return integer id
function Police.target.global(group, entityType, options, distance)
    return trackTarget(group, exports.qbtarget:addGlobalType(entityType, options, distance), function(id)
        exports.qbtarget:removeGlobalType(entityType, id)
    end)
end

---@param group string
---@param options QBTargetBoxZoneOptions
---@return integer id
function Police.target.box(group, options)
    return trackTarget(group, exports.qbtarget:addBoxZone(options), function(id)
        exports.qbtarget:removeZone(id)
    end)
end

---@param group string
---@param options QBTargetSphereZoneOptions
---@return integer id
function Police.target.sphere(group, options)
    return trackTarget(group, exports.qbtarget:addSphereZone(options), function(id)
        exports.qbtarget:removeZone(id)
    end)
end

AddEventHandler('onClientResourceStop', function(resourceName)
    -- qbtarget has already discarded its registrations. Retaining its old IDs
    -- would let a fresh instance remove unrelated targets if it reuses an ID.
    if resourceName == 'qbtarget' then Police.targetGroups = {} end
end)

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
function isHandcuffed()
    return Police.cuffed
end
exports('isHandcuffed', isHandcuffed)
