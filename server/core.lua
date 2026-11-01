-- Shared server-side state for this resource. A bare global table, same
-- convention kora_admin's `Admin`/qbtarget's `ServerTarget`/qbinventory's
-- `QbInventory` use for cross-file organisation within one resource.

Police = Police or {}

-- src -> src. Both tables are kept as plain in-memory maps: escort/drag are
-- ephemeral relationships between two currently-online players, not durable
-- state, so there is nothing worth persisting through metadata here.
Police.escorted = Police.escorted or {}   -- [targetSrc] = officerSrc
Police.kidnapped = Police.kidnapped or {} -- [targetSrc] = draggerSrc
Police.tracked = Police.tracked or {}     -- [targetSrc] = true (bracelet/tracker active)

-- plate -> { reason, flaggedBy, flaggedAt }
Police.plateFlags = Police.plateFlags or {}

-- citizenid -> generated fingerprint id (deterministic per person, generated once)
Police.fingerprints = Police.fingerprints or {}

-- Lightweight legacy "world evidence" markers (blood drops / casings /
-- fingerprints) -- id -> { type, coords, ownerId, createdAt }. Compat-only
-- surface for third-party scripts expecting these qb-policejob events to
-- exist; deliberately not a full CSI system.
Police.worldEvidence = Police.worldEvidence or {}
Police.nextEvidenceId = Police.nextEvidenceId or 1

-- citizenid -> { [evidenceId] = true }, what a given player has collected.
Police.collectedEvidence = Police.collectedEvidence or {}

---@param a integer
---@param b integer
---@return number
function Police.distanceBetween(a, b)
    if GetPlayerRoutingBucket(a) ~= GetPlayerRoutingBucket(b) then return math.huge end
    local pedA, pedB = GetPlayerPed(a), GetPlayerPed(b)
    if not pedA or pedA == 0 or not pedB or pedB == 0 then return math.huge end
    return #(GetEntityCoords(pedA) - GetEntityCoords(pedB))
end

-- Legacy metadata flags are written as booleans by kora_ambulance but other
-- medical resources use 1/0 or "true"; accept all of them.
local function truthy(value)
    return value == true or value == 1 or value == 'true'
end

---Whether a player is last-stand or dead. Order: kora_ambulance live state
---(statebag, then export), legacy isdead/inlaststand metadata, and -- only when
---Config.incapacitated.pedHealthFallback is on -- the server-side ped health.
---@param src integer
---@return boolean
function Police.isDowned(src)
    local cfg = Config.incapacitated or {}
    if cfg.ambulance ~= false and GetResourceState('kora_ambulance') == 'started' then
        local okBag, bag = pcall(function() return Player(src).state.emsDown end)
        if okBag and bag and bag ~= 'alive' then return true end
        local okStatus, status = pcall(function() return exports.kora_ambulance:getPatientStatus(src) end)
        if okStatus and type(status) == 'table' and (status.state == 'laststand' or status.state == 'dead') then
            return true
        end
    end
    if truthy(exports.kora_core:getMetaData(src, 'isdead')) or truthy(exports.kora_core:getMetaData(src, 'inlaststand')) then
        return true
    end
    if cfg.pedHealthFallback == true then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            local health = GetEntityHealth(ped)
            -- GTA treats a player ped at or below 100 health as fatally injured.
            if health and health <= 100 then return true end
        end
    end
    return false
end

---Whether a target may be robbed/dragged: downed and/or cuffed, each gated by Config.incapacitated.
---@param src integer
---@return boolean
function Police.isIncapacitated(src)
    local cfg = Config.incapacitated or {}
    if cfg.cuffed ~= false and Police.isCuffed(src) then return true end
    if cfg.downed ~= false and Police.isDowned(src) then return true end
    return false
end

---@param src integer
---@param entity integer
---@return number
function Police.distanceToEntity(src, entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return math.huge end
    if GetPlayerRoutingBucket(src) ~= GetEntityRoutingBucket(entity) then return math.huge end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return math.huge end
    return #(GetEntityCoords(ped) - GetEntityCoords(entity))
end

---@param plate string
---@return integer|nil
function Police.findVehicleByPlate(plate)
    local wanted = tostring(plate):gsub('^%s+', ''):gsub('%s+$', ''):upper()
    for _, vehicle in ipairs(GetAllVehicles()) do
        local actual = GetVehicleNumberPlateText(vehicle)
        actual = actual and actual:gsub('^%s+', ''):gsub('%s+$', ''):upper()
        if actual == wanted then return vehicle end
    end
    return nil
end

---@param src integer
---@return table|nil job
local function job(src)
    return exports.kora_core:getJob(src)
end
Police.job = job

---@param src integer
---@param onDutyOnly boolean|nil
---@return boolean
function Police.isPolice(src, onDutyOnly)
    local j = job(src)
    if not j or j.name ~= Config.police.job then return false end
    if onDutyOnly ~= false and not j.onduty then return false end
    return true
end

---@param src integer
---@return integer grade level, or -1 if not a police officer
function Police.gradeLevel(src)
    local j = job(src)
    if not j or j.name ~= Config.police.job then return -1 end
    return tonumber(j.grade and j.grade.level) or 0
end

---@param src integer
---@return boolean
function Police.isCuffed(src)
    return exports.kora_core:getMetaData(src, 'ishandcuffed') == true
end

local function citizenId(src)
    return exports.kora_core:getPlayerData(src, { 'citizenid' })
end
Police.citizenId = citizenId

---Tells one player something via kora_lib notify (no dependence on the QBCore:Notify compat event).
---@param src integer
---@param message string
---@param type_ string|nil `error`, `success` or `inform` (default `error`)
function Police.notify(src, message, type_)
    if not src or not message then return end
    Kora.notify.send(src, { message = message, type = type_ or "error" })
end

AddEventHandler('playerDropped', function()
    local src = source
    -- Tell the surviving side so it does not keep a stale escort/drag state
    -- (a stale draggedTarget would hide the Drag option until relog).
    local officer = Police.escorted[src]
    if officer then TriggerClientEvent('qbpolice:client:escortStopSelf', officer, src) end
    local dragger = Police.kidnapped[src]
    if dragger then TriggerClientEvent('qbpolice:client:dragStopSelf', dragger, src) end
    Police.escorted[src] = nil
    Police.kidnapped[src] = nil
    Police.tracked[src] = nil
    for target, owner in pairs(Police.escorted) do
        if owner == src then
            Police.escorted[target] = nil
            TriggerClientEvent('qbpolice:client:escortStop', target)
        end
    end
    for target, owner in pairs(Police.kidnapped) do
        if owner == src then
            Police.kidnapped[target] = nil
            TriggerClientEvent('qbpolice:client:dragStop', target)
        end
    end
end)
