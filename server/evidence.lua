-- Evidence storage. Two separate mechanisms, both reusing qbinventory as-is:
--
-- 1. The dedicated `QbInventory.evidence`/`.confiscation` seize/open/release
--    API (server/containers.lua) is a genuine "headless core" seam: it has no
--    exports() registration and no net event, only bare Lua functions on a
--    table private to qbinventory's own resource VM (verified by grepping
--    qbinventory's own source -- nothing outside server/containers.lua itself
--    ever reaches QbInventory.evidence). It is therefore NOT callable from
--    this resource. Per the plan, qbpolice still supplies its access-policy
--    callback (Config.qbinventory.containers.evidence.access, additively
--    edited directly in qbinventory/config.lua -- Config is a resource-local
--    global with no cross-resource setter export for this one field) so that
--    boundary is genuinely ready for whatever in-VM caller qbinventory itself
--    gains in the future.
--
-- 2. What qbpolice actually wires its own evidence-locker UI onto today is
--    qbinventory's ordinary, fully cross-resource-reachable STASH domain
--    (`RegisterStash`, exported) -- a shared, job-gated container for
--    processed evidence. This uses zero new inventory/storage code (slots,
--    weight, access, persistence are all qbinventory's existing stash
--    machinery); it's just registered with police-appropriate parameters.
--    Seizing an item off a restrained suspect (see server/seize.lua) still
--    goes through qbinventory's real player-inspection + transfer protocol,
--    not a bespoke mechanism.

CreateThread(function()
    exports.qbinventory:RegisterStash(
        Config.evidence.lockerStashId, Config.evidence.lockerLabel,
        Config.evidence.lockerSlots, Config.evidence.lockerMaxWeight,
        nil, { [Config.police.job] = Config.evidence.minGradeToAccess },
        Config.evidence.lockerCoords
    )
end)

-- Legacy "world evidence" compat -- blood drops / casings / fingerprints left
-- at a scene, and a per-officer collected-evidence list. Deliberately a thin
-- marker registry (id/type/coords/owner), not a new CSI minigame: the
-- checklist obligation is that these event names exist and behave sanely for
-- a third-party script that still calls them, not a new feature to design.

---@param evType string 'blood'|'fingerprint'|'casing'
---@param coords table
---@param ownerCitizenId string|nil
---@return integer id
local evidenceCreatedAt = {}

local function markerCount()
    local count = 0
    for _ in pairs(Police.worldEvidence) do count = count + 1 end
    return count
end

local function evictOldestMarker()
    local oldestId, oldestAt
    for id, marker in pairs(Police.worldEvidence) do
        if not oldestAt or marker.createdAt < oldestAt then oldestId, oldestAt = id, marker.createdAt end
    end
    if oldestId then Police.worldEvidence[oldestId] = nil end
end

local function createWorldEvidence(src, evType)
    local now = GetGameTimer()
    if evidenceCreatedAt[src] and now - evidenceCreatedAt[src] < Config.evidence.createCooldown then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    evidenceCreatedAt[src] = now

    while markerCount() >= Config.evidence.maxWorldMarkers do evictOldestMarker() end

    local id = Police.nextEvidenceId
    Police.nextEvidenceId = Police.nextEvidenceId + 1
    local coords = GetEntityCoords(ped)
    Police.worldEvidence[id] = {
        type = evType,
        coords = coords,
        ownerId = Police.citizenId(src),
        bucket = GetPlayerRoutingBucket(src),
        createdAt = now,
        expiresAt = now + Config.evidence.worldMarkerTtl,
    }

    for _, src in ipairs(exports.qbcore:getPlayersByJob(Config.police.job, true)) do
        TriggerClientEvent('qbpolice:client:worldEvidenceCreated', src, id, evType, coords)
    end
    return id
end

RegisterNetEvent('evidence:server:CreateBloodDrop', function(coords, citizenId)
    createWorldEvidence(source, 'blood')
end)
RegisterNetEvent('evidence:server:CreateFingerDrop', function(coords, citizenId)
    createWorldEvidence(source, 'fingerprint')
end)
RegisterNetEvent('evidence:server:CreateCasing', function(coords, citizenId)
    createWorldEvidence(source, 'casing')
end)

RegisterNetEvent('evidence:server:AddToInventory', function(evidenceId)
    local src = source
    local cid = Police.citizenId(src)
    local marker = Police.worldEvidence[tonumber(evidenceId)]
    if not cid or not marker or not Police.isPolice(src) then return end
    if marker.expiresAt <= GetGameTimer() then Police.worldEvidence[tonumber(evidenceId)] = nil; return end
    if marker.bucket ~= GetPlayerRoutingBucket(src) then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(marker.coords.x, marker.coords.y, marker.coords.z)) > Config.evidence.collectDistance then return end
    Police.collectedEvidence[cid] = Police.collectedEvidence[cid] or {}
    Police.collectedEvidence[cid][tonumber(evidenceId)] = true
    Police.worldEvidence[tonumber(evidenceId)] = nil
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = GetGameTimer()
        for id, marker in pairs(Police.worldEvidence) do
            if marker.expiresAt <= now then Police.worldEvidence[id] = nil end
        end
    end
end)

AddEventHandler('playerDropped', function()
    evidenceCreatedAt[source] = nil
end)
RegisterNetEvent('evidence:server:RemoveFromInventory', function(evidenceId)
    local cid = Police.citizenId(source)
    if cid and Police.collectedEvidence[cid] then Police.collectedEvidence[cid][tonumber(evidenceId)] = nil end
end)
RegisterNetEvent('evidence:server:ClearInventory', function()
    local cid = Police.citizenId(source)
    if cid then Police.collectedEvidence[cid] = {} end
end)
