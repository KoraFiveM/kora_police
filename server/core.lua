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

---@param src integer
---@return boolean
function Police.isIncapacitated(src)
    return Police.isCuffed(src)
        or exports.kora_core:getMetaData(src, 'isdead') == true
        or exports.kora_core:getMetaData(src, 'inlaststand') == true
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

AddEventHandler('playerDropped', function()
    local src = source
    Police.escorted[src] = nil
    Police.kidnapped[src] = nil
    Police.tracked[src] = nil
    for target, officer in pairs(Police.escorted) do
        if officer == src then Police.escorted[target] = nil end
    end
    for target, dragger in pairs(Police.kidnapped) do
        if dragger == src then Police.kidnapped[target] = nil end
    end
end)
