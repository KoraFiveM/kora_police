-- Evidence storage. Two separate mechanisms, both reusing kora_inventory as-is:
--
-- 1. The dedicated `KoraInventory.evidence`/`.confiscation` seize/open/release
--    API (server/containers.lua) is a genuine "headless core" seam: it has no
--    exports() registration and no net event, only bare Lua functions on a
--    table private to kora_inventory's own resource VM (verified by grepping
--    kora_inventory's own source -- nothing outside server/containers.lua itself
--    ever reaches KoraInventory.evidence). It is therefore NOT callable from
--    this resource. Per the plan, kora_police still supplies its access-policy
--    callback (Config.kora_inventory.containers.evidence.access, additively
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

local evidenceCreatedAt = {}

local function removeWorldEvidence(id)
    if not Police.worldEvidence[id] then return end
    Police.worldEvidence[id] = nil
    -- Former observers may have gone off duty since the marker was created.
    TriggerClientEvent('kora_police:client:worldEvidenceRemoved', -1, id)
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

    for _, officer in ipairs(exports.kora_core:getPlayersByJob(Config.police.job, true)) do
        TriggerClientEvent('kora_police:client:worldEvidenceCreated', officer, id, evType, coords)
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
        local _, err = Kora.sql.execute([[INSERT INTO `kora_police_ballistic_casings`
            (`case_id`,`round_id`,`weapon_serial`,`weapon_name`,`ammo_type`,`lot`,`x`,`y`,`z`,`bucket`)
            VALUES (?,?,?,?,?,?,?,?,?,?)]], {
            caseId, round.id, round.weaponSerial, round.weapon, round.ammoType, round.lot,
            coords.x, coords.y, coords.z, GetPlayerRoutingBucket(src),
        })
        if err then print(('^1[kora_police:ballistics]^7 could not save casing %s: %s'):format(caseId, tostring(err))) end
    end)
    return caseId
end

-- kora_inventory is the only producer and has already server-validated the
-- equipped weapon and consumed the exact round before it emits this event.
AddEventHandler('kora_inventory:server:weaponRoundFired', function(src, round)
    Police.createBallisticCasing(tonumber(src), round)
end)

-- Stock argument orders are (citizenid, bloodtype, coords), (coords) and
-- (weapon, coords). None of them is trusted: the marker is created at the
-- caller's own position, owned by the caller.
RegisterNetEvent('evidence:server:CreateBloodDrop', function()
    createWorldEvidence(source, 'blood')
end)
RegisterNetEvent('evidence:server:CreateFingerDrop', function()
    createWorldEvidence(source, 'fingerprint')
end)
RegisterNetEvent('evidence:server:CreateCasing', function()
    createWorldEvidence(source, 'casing')
end)

---Item the officer must hold to package evidence (Config.evidence.bagItem).
local function bagItem()
    return Config.evidence.bagItem or 'empty_evidence_bag'
end

---Notification for a failed bag removal: a clear "you need X" message when the
---bag is simply missing, the inventory's own reason for any other failure.
local function bagFailureMessage(removeErr, what)
    if removeErr and not tostring(removeErr):lower():find('not enough', 1, true) then return removeErr end
    local template = Config.evidence.missingBagMessage or 'You need an %s to collect %s.'
    return template:format(Config.evidence.bagLabel or 'Evidence Bag', what)
end

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
        local removed, removeErr = exports.kora_inventory:RemoveItem(src, bagItem(), 1, false, 'ballistic-casing-collection')
        if not removed then
            Kora.notify.send(src, { title = 'Evidence', message = bagFailureMessage(removeErr, 'casings'), type = 'error' })
            return
        end
        local added, addErr = exports.kora_inventory:AddItem(src, 'filled_evidence_bag', 1, false, {
            label = 'Ballistic Casing ' .. marker.ballistic.caseId,
            type = 'ballistic_casing', caseId = marker.ballistic.caseId,
        }, 'ballistic-casing-collection')
        if not added then
            exports.kora_inventory:AddItem(src, bagItem(), 1, false, {}, 'ballistic-casing-rollback')
            Kora.notify.send(src, { title = 'Evidence', message = addErr or 'Could not package casing.', type = 'error' })
            return
        end
        CreateThread(function()
            local _, err = Kora.sql.execute('UPDATE `kora_police_ballistic_casings` SET `collected_by` = ?, `collected_at` = CURRENT_TIMESTAMP WHERE `case_id` = ?',
                { cid, marker.ballistic.caseId })
            if err then print(('^1[kora_police:ballistics]^7 could not mark collected casing: %s'):format(tostring(err))) end
        end)
    end
    Police.collectedEvidence[cid] = Police.collectedEvidence[cid] or {}
    Police.collectedEvidence[cid][evidenceId] = true
    removeWorldEvidence(evidenceId)
    Kora.notify.send(src, { title = 'Evidence', message = 'Evidence collected.', type = 'success' })
end)

---Server-only lookup for the authorised MDT. No client event exposes this
---row, particularly not `weapon_serial`; investigation stages decide when it
---may be shown to an officer.
function Police.getBallisticCasing(caseId)
    if type(caseId) ~= 'string' or #caseId > 64 then return nil, Kora.lang('Notify.invalid_case_id') end
    return Kora.sql.single('SELECT * FROM `kora_police_ballistic_casings` WHERE `case_id` = ?', { caseId })
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

-- Stock qb-policejob evidence events. Stock lets any client mint evidence-bag
-- metadata, delete any marker and broadcast every sample to everyone; here the
-- marker registry above stays the only authority: officer + duty + distance +
-- bucket checked, the type must match, and item metadata is built server-side.
local function sameBucketAndNear(src, marker, distance)
    if marker.bucket ~= GetPlayerRoutingBucket(src) then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(marker.coords.x, marker.coords.y, marker.coords.z)) <= distance
end

local function hex(value)
    return (tostring(value):gsub('.', function(c) return ('%02x'):format(c:byte()) end))
end

local function sampleInfo(marker)
    if marker.ballistic then
        return { label = 'Ballistic Casing ' .. marker.ballistic.caseId, type = 'ballistic_casing', caseId = marker.ballistic.caseId }
    end
    if marker.type == 'blood' then
        return { label = 'Blood Sample', type = 'blood', dnalabel = marker.ownerId and hex(marker.ownerId) or nil }
    end
    if marker.type == 'fingerprint' then
        return { label = 'Fingerprint', type = 'fingerprint', fingerprint = marker.ownerId and Police.getFingerprint(marker.ownerId) or nil }
    end
    return { label = 'Casing', type = 'casing' }
end

local function collectSample(src, evidenceId, wantedType)
    evidenceId = tonumber(evidenceId)
    local marker = evidenceId and Police.worldEvidence[evidenceId]
    if not marker or marker.type ~= wantedType or not Police.isPolice(src) then return end
    if marker.expiresAt <= GetGameTimer() then removeWorldEvidence(evidenceId); return end
    if not sameBucketAndNear(src, marker, Config.evidence.collectDistance) then return end
    local removed, removeErr = exports.kora_inventory:RemoveItem(src, bagItem(), 1, false, 'evidence-sample-collection')
    if not removed then
        Kora.notify.send(src, { title = 'Evidence', message = bagFailureMessage(removeErr, marker.type == 'casing' and 'casings' or 'evidence samples'), type = 'error' })
        return
    end
    local added, addErr = exports.kora_inventory:AddItem(src, 'filled_evidence_bag', 1, false, sampleInfo(marker), 'evidence-sample-collection')
    if not added then
        exports.kora_inventory:AddItem(src, bagItem(), 1, false, {}, 'evidence-sample-rollback')
        Kora.notify.send(src, { title = 'Evidence', message = addErr or 'Could not package evidence.', type = 'error' })
        return
    end
    local cid = Police.citizenId(src)
    if cid then
        Police.collectedEvidence[cid] = Police.collectedEvidence[cid] or {}
        Police.collectedEvidence[cid][evidenceId] = true
    end
    removeWorldEvidence(evidenceId)
end

RegisterNetEvent('evidence:server:AddBlooddropToInventory', function(bloodId) collectSample(source, bloodId, 'blood') end)
RegisterNetEvent('evidence:server:AddFingerprintToInventory', function(fingerId) collectSample(source, fingerId, 'fingerprint') end)
RegisterNetEvent('evidence:server:AddCasingToInventory', function(casingId) collectSample(source, casingId, 'casing') end)

local function clearMarkers(src, list, wantedType)
    if type(list) ~= 'table' or not Police.isPolice(src) then return end
    local cleared = 0
    for _, rawId in ipairs(list) do
        cleared = cleared + 1
        if cleared > Config.evidence.clearMaxMarkers then return end
        local id = tonumber(rawId)
        local marker = id and Police.worldEvidence[id]
        if marker and marker.type == wantedType and sameBucketAndNear(src, marker, Config.evidence.clearDistance) then
            removeWorldEvidence(id)
        end
    end
end

RegisterNetEvent('evidence:server:ClearBlooddrops', function(list) clearMarkers(source, list, 'blood') end)
RegisterNetEvent('evidence:server:ClearCasings', function(list) clearMarkers(source, list, 'casing') end)

Police.playerStatus = Police.playerStatus or {}

---Stock `evidence:server:UpdateStatus({ [id] = { text, time } })`: only known
---status ids survive, with the server's own label and a bounded lifetime.
RegisterNetEvent('evidence:server:UpdateStatus', function(data)
    local src = source
    if type(data) ~= 'table' then Police.playerStatus[src] = nil; return end
    local clean, any = {}, false
    for id in pairs(data) do
        local label = type(id) == 'string' and Config.evidence.statuses[id]
        if label then clean[id] = label; any = true end
    end
    Police.playerStatus[src] = any and { labels = clean, expiresAt = GetGameTimer() + Config.evidence.statusTtl } or nil
end)

---@param target integer
---@return string[]
function Police.getPlayerStatusList(target)
    local entry = Police.playerStatus[target]
    if not entry then return {} end
    if entry.expiresAt <= GetGameTimer() then Police.playerStatus[target] = nil; return {} end
    local ids = {}
    for id in pairs(entry.labels) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do out[#out + 1] = entry.labels[id] end
    return out
end

AddEventHandler('playerDropped', function() Police.playerStatus[source] = nil end)
