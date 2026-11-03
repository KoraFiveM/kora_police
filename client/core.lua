-- Shared client-side state. Bare global table, same cross-file convention as
-- the server realm's Police table (and kora_admin's own Admin table).

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

---Replaces one feature's kora_target registrations without stacking options.
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
    return trackTarget(group, exports.kora_target:addGlobalType(entityType, options, distance), function(id)
        exports.kora_target:removeGlobalType(entityType, id)
    end)
end

---@param group string
---@param options QBTargetBoxZoneOptions
---@return integer id
function Police.target.box(group, options)
    return trackTarget(group, exports.kora_target:addBoxZone(options), function(id)
        exports.kora_target:removeZone(id)
    end)
end

---@param group string
---@param options QBTargetSphereZoneOptions
---@return integer id
function Police.target.sphere(group, options)
    return trackTarget(group, exports.kora_target:addSphereZone(options), function(id)
        exports.kora_target:removeZone(id)
    end)
end

AddEventHandler('onClientResourceStop', function(resourceName)
    -- kora_target has already discarded its registrations. Retaining its old IDs
    -- would let a fresh instance remove unrelated targets if it reuses an ID.
    if resourceName == 'kora_target' then Police.targetGroups = {} end
end)

function Police.isOnDuty()
    local job = exports.kora_core:getPlayerData({ 'job' })
    return job ~= nil and job.name == Config.police.job and job.onduty == true
end

function Police.myGradeLevel()
    local job = exports.kora_core:getPlayerData({ 'job' })
    if not job or job.name ~= Config.police.job then return -1 end
    return tonumber(job.grade and job.grade.level) or 0
end

function Police.notify(message, type_)
    Kora.notify.send({ message = message, type = type_ or 'info' })
end

-- The server publishes the restraint on the replicated player state bag
-- (`koraCuffed`, `koraCuffedSoft`, written only by server/cuff.lua) and also
-- sends this event. Either one lands here; the event always re-applies the
-- visuals (a re-cuff refreshes them), the bag only on a change.
RegisterNetEvent('qbpolice:client:cuffed', function(cuffed, soft, otherSrc)
    Police.cuffed = cuffed == true
    Police.soft = soft == true
    TriggerEvent('qbpolice:client:cuffStateChanged', Police.cuffed, Police.soft, otherSrc)
end)

---@param cuffed boolean|nil
---@param soft boolean|nil
function Police.syncCuffState(cuffed, soft)
    cuffed, soft = cuffed == true, soft == true
    if cuffed == Police.cuffed and soft == Police.soft then return end
    Police.cuffed, Police.soft = cuffed, soft
    TriggerEvent('qbpolice:client:cuffStateChanged', cuffed, soft)
end

---Replicated state bag of the player that owns `ped`, nil for anything else.
---@param ped integer
---@return table|nil
local function playerStateOf(ped)
    local index = NetworkGetPlayerIndexFromPed(ped)
    if not index or index == -1 then return nil end
    local serverId = GetPlayerServerId(index)
    if not serverId or serverId <= 0 then return nil end
    return Player(serverId).state
end

---Whether the player owning `ped` is cuffed, from the replicated bag (the same
---source for every client, unlike the local ped's animation state).
---@param ped integer
---@return boolean
function Police.isPedCuffed(ped)
    local state = playerStateOf(ped)
    return state ~= nil and state.koraCuffed == true
end

---Whether an `emsDown` bag value means last stand or dead. kora_ambulance
---publishes 'laststand'/'dead' while down and `false` (not 'alive') for a
---living player, at every login and revive, so only a truthy value other than
---'alive' is downed (the same rule as Police.isDowned on the server).
---@param value any
---@return boolean
function Police.isDownValue(value)
    return value ~= nil and value ~= false and value ~= 'alive'
end

---Cuffed, or downed when Config.incapacitated allows it: who may be robbed or dragged.
---@param ped integer
---@return boolean
function Police.isPedRestrained(ped)
    local state = playerStateOf(ped)
    if not state then return false end
    local cfg = Config.incapacitated or {}
    if cfg.cuffed ~= false and state.koraCuffed == true then return true end
    return cfg.downed ~= false and Police.isDownValue(state.emsDown)
end

---Legacy client export.
function isHandcuffed()
    return Police.cuffed
end
exports('isHandcuffed', isHandcuffed)

-- Upstream consumers use a capital I and the qb-policejob resource identity.
exports('IsHandcuffed', isHandcuffed)
Kora.compat.provideExport('qb-policejob', 'IsHandcuffed', isHandcuffed)
