-- Evidence storage. Two separate mechanisms, both reusing kora_inventory as-is:
--
-- 1. The dedicated `QbInventory.evidence`/`.confiscation` seize/open/release
--    API (server/containers.lua) is a genuine "headless core" seam: it has no
--    exports() registration and no net event, only bare Lua functions on a
--    table private to kora_inventory's own resource VM (verified by grepping
--    kora_inventory's own source -- nothing outside server/containers.lua itself
--    ever reaches QbInventory.evidence). It is therefore NOT callable from
--    this resource. Per the plan, kora_police still supplies its access-policy
--    callback (Config.qbinventory.containers.evidence.access, additively
--    edited directly in kora_inventory/config.lua -- Config is a resource-local
--    global with no cross-resource setter export for this one field) so that
--    boundary is genuinely ready for whatever in-VM caller kora_inventory itself
--    gains in the future.
--
-- 2. What kora_police actually wires its own evidence-locker UI onto today is
--    kora_inventory's ordinary, fully cross-resource-reachable STASH domain
--    (`RegisterStash`, exported) -- a shared, job-gated container for
--    processed evidence. This uses zero new inventory/storage code (slots,
--    weight, access, persistence are all kora_inventory's existing stash
--    machinery); it's just registered with police-appropriate parameters.
--    Seizing an item off a restrained suspect (see server/seize.lua) still
--    goes through kora_inventory's real player-inspection + transfer protocol,
--    not a bespoke mechanism.

-- Registers the evidence-locker stash against kora_inventory. Called once at
-- load AND again on every kora_inventory onResourceStart -- a kora_inventory
-- restart mid-session wipes kora_inventory's own stash table, and a
-- `dependency 'kora_inventory'` declaration only guarantees start order on a
-- fresh boot, not survival of that later restart.
local function registerEvidenceLocker()
    exports.kora_inventory:RegisterStash(
        Config.evidence.lockerStashId, Config.evidence.lockerLabel,
        Config.evidence.lockerSlots, Config.evidence.lockerMaxWeight,
        nil, { [Config.police.job] = Config.evidence.minGradeToAccess },
        Config.evidence.lockerCoords
    )
end

CreateThread(registerEvidenceLocker)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'kora_inventory' then CreateThread(registerEvidenceLocker) end
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

local function removeWorldEvidence(id)
    if not Police.worldEvidence[id] then return end
    Police.worldEvidence[id] = nil
    -- Former observers may have gone off duty since the marker was created.
    TriggerClientEvent('qbpolice:client:worldEvidenceRemoved', -1, id)
end

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
    if oldestId then removeWorldEvidence(oldestId) end
end

local function createWorldEvidence(src, evType, ballistic, suppliedCoords)
    local now = GetGameTimer()
    if evidenceCreatedAt[src] and now - evidenceCreatedAt[src] < Config.evidence.createCooldown then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    evidenceCreatedAt[src] = now

    while markerCount() >= Config.evidence.maxWorldMarkers do evictOldestMarker() end

    local id = Police.nextEvidenceId
    Police.nextEvidenceId = Police.nextEvidenceId + 1
    local coords = suppliedCoords or GetEntityCoords(ped)
    Police.worldEvidence[id] = {
        type = evType,
        coords = coords,
        ownerId = Police.citizenId(src),
        bucket = GetPlayerRoutingBucket(src),
        createdAt = now,
        expiresAt = now + Config.evidence.worldMarkerTtl,
        ballistic = ballistic,
    }

    for _, src in ipairs(exports.kora_core:getPlayersByJob(Config.police.job, true)) do
        TriggerClientEvent('qbpolice:client:worldEvidenceCreated', src, id, evType, coords)
    end
    return id
end

local function casingId()
    return ('CS-%d-%06d-%06d'):format(os.time(), math.random(0, 999999), math.random(0, 999999))
end

---Create a casing from kora_inventory's server-owned fired-round event. This is
---an export rather than a net event: neither clients nor legacy resources may
---supply a serial, round, or casing position.
---@param src integer
---@param round table
---@return string|nil caseId
function Police.createBallisticCasing(src, round)
    local policy = (Config.evidence or {}).ballistic or {}
    if policy.enabled ~= true or type(round) ~= 'table' then return nil end
    if type(round.id) ~= 'string' or type(round.weaponSerial) ~= 'string' or type(round.weapon) ~= 'string' then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end

    local origin = GetEntityCoords(ped)
    local offset = math.max(0, tonumber(policy.casingOffset) or 0.75)
    local coords = vector3(origin.x + ((math.random() * 2.0 - 1.0) * offset),
        origin.y + ((math.random() * 2.0 - 1.0) * offset), origin.z)
    local caseId = casingId()
    local details = {
        caseId = caseId,
        -- All of these remain server-only. The marker client only receives a
        -- type and coordinates, and a collected item only has `caseId`.
        roundId = round.id,
        weaponSerial = round.weaponSerial,
        weapon = round.weapon,
        ammoType = round.ammoType,
        lot = round.lot,
    }
    local id = createWorldEvidence(src, 'casing', details, coords)
    if not id then return nil end

    CreateThread(function()
        local _, err = QB.sql.execute([[INSERT INTO `qbpolice_ballistic_casings`
            (`case_id`,`round_id`,`weapon_serial`,`weapon_name`,`ammo_type`,`lot`,`x`,`y`,`z`,`bucket`)
            VALUES (?,?,?,?,?,?,?,?,?,?)]], {
            caseId, round.id, round.weaponSerial, round.weapon, round.ammoType, round.lot,
            coords.x, coords.y, coords.z, GetPlayerRoutingBucket(src),
        })
        if err then print(('^1[qbpolice:ballistics]^7 could not save casing %s: %s'):format(caseId, tostring(err))) end
    end)
    return caseId
end

-- kora_inventory is the only producer and has already server-validated the
-- equipped weapon and consumed the exact round before it emits this event.
AddEventHandler('qbinventory:server:weaponRoundFired', function(src, round)
    Police.createBallisticCasing(tonumber(src), round)
end)

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
    evidenceId = tonumber(evidenceId)
    local cid = Police.citizenId(src)
    local marker = Police.worldEvidence[evidenceId]
    if not cid or not marker or not Police.isPolice(src) then return end
    if marker.expiresAt <= GetGameTimer() then removeWorldEvidence(evidenceId); return end
    if marker.bucket ~= GetPlayerRoutingBucket(src) then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(marker.coords.x, marker.coords.y, marker.coords.z)) > Config.evidence.collectDistance then return end
    if marker.ballistic then
        local removed, removeErr = exports.kora_inventory:RemoveItem(src, 'empty_evidence_bag', 1, false, 'ballistic-casing-collection')
        if not removed then
            QB.notify.send(src, { title = 'Evidence', message = removeErr or 'An empty evidence bag is required.', type = 'error' })
            return
        end
        local added, addErr = exports.kora_inventory:AddItem(src, 'filled_evidence_bag', 1, false, {
            label = 'Ballistic Casing ' .. marker.ballistic.caseId,
            type = 'ballistic_casing', caseId = marker.ballistic.caseId,
        }, 'ballistic-casing-collection')
        if not added then
            exports.kora_inventory:AddItem(src, 'empty_evidence_bag', 1, false, {}, 'ballistic-casing-rollback')
            QB.notify.send(src, { title = 'Evidence', message = addErr or 'Could not package casing.', type = 'error' })
            return
        end
        CreateThread(function()
            local _, err = QB.sql.execute('UPDATE `qbpolice_ballistic_casings` SET `collected_by` = ?, `collected_at` = CURRENT_TIMESTAMP WHERE `case_id` = ?',
                { cid, marker.ballistic.caseId })
            if err then print(('^1[qbpolice:ballistics]^7 could not mark collected casing: %s'):format(tostring(err))) end
        end)
    end
    Police.collectedEvidence[cid] = Police.collectedEvidence[cid] or {}
    Police.collectedEvidence[cid][evidenceId] = true
    removeWorldEvidence(evidenceId)
    QB.notify.send(src, { title = 'Evidence', message = 'Evidence collected.', type = 'success' })
end)

---Server-only lookup for the authorised MDT. No client event exposes this
---row, particularly not `weapon_serial`; investigation stages decide when it
---may be shown to an officer.
function Police.getBallisticCasing(caseId)
    if type(caseId) ~= 'string' or #caseId > 64 then return nil, 'invalid case id' end
    return QB.sql.single('SELECT * FROM `qbpolice_ballistic_casings` WHERE `case_id` = ?', { caseId })
end

exports('CreateBallisticCasing', Police.createBallisticCasing)
exports('GetBallisticCasing', Police.getBallisticCasing)

CreateThread(function()
    while true do
        Wait(60000)
        local now = GetGameTimer()
        for id, marker in pairs(Police.worldEvidence) do
            if marker.expiresAt <= now then removeWorldEvidence(id) end
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
