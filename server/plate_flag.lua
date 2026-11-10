-- Plate flags (BOLO/stolen/wanted) -- a small in-memory registry an officer
-- can add/remove from, checked automatically whenever a vehicle spawns
-- nearby a patrol car (client/dispatch.lua polls `IsPlateFlagged`), firing
-- the legacy `FlaggedPlateTriggered` event at the flagging officer's job.

-- kora_mdt owns BOLOs (`kora_mdt_bolos`) and its Vehicles/BOLO views read only
-- that table, so a flag kept just in this file's memory never reached the MDT.
-- Flagging therefore also writes an active vehicle BOLO there
-- (Config.plateFlags.mirrorToMdt); everything is skipped quietly when kora_mdt
-- or its table is not installed.
local function mdtMirrorEnabled()
    local cfg = Config.plateFlags or {}
    return cfg.mirrorToMdt ~= false and Kora.sql ~= nil and GetResourceState('kora_mdt') == 'started'
end

local function mdtWarn(action, err)
    print(('^3[kora_police:plateFlag]^7 could not %s the kora_mdt BOLO: %s'):format(action, tostring(err)))
end

---Plates read from a vehicle come space-padded and mixed case; the MDT looks plates up trimmed and upper-case.
---@param plate any
---@return string|nil
local function normalizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:match('^%s*(.-)%s*$'):upper()
    if plate == '' or #plate > 15 then return nil end
    return plate
end

local function mdtFlag(officerSrc, plate, reason)
    if not mdtMirrorEnabled() then return end
    local days = math.max(1, math.floor(tonumber((Config.plateFlags or {}).days) or 7))
    local title = ('Flagged plate %s'):format(plate)
    local author = Police.citizenId(officerSrc) or 'police'
    local ok, err = pcall(function()
        local existing = Kora.sql.single("SELECT `id` FROM `kora_mdt_bolos` WHERE `subject_type` = 'vehicle' AND `subject_identifier` = ? AND `status` = 'active' LIMIT 1", { plate })
        if existing then
            return Kora.sql.update('UPDATE `kora_mdt_bolos` SET `description` = ?, `expires_at` = DATE_ADD(NOW(), INTERVAL ? DAY) WHERE `id` = ?', { reason:sub(1, 1500), days, existing.id })
        end
        local id, insertErr = Kora.sql.insert([[INSERT INTO `kora_mdt_bolos`
            (`subject_type`,`subject_identifier`,`title`,`description`,`author_citizenid`,`expires_at`)
            VALUES ('vehicle',?,?,?,?,DATE_ADD(NOW(), INTERVAL ? DAY))]], { plate, title, reason:sub(1, 1500), author, days })
        if not id then error(insertErr or 'insert failed', 0) end
    end)
    if not ok then mdtWarn('write', err) end
end

---@return integer resolved how many active MDT BOLOs were closed
local function mdtUnflag(plate)
    if not mdtMirrorEnabled() then return 0 end
    local ok, changed = pcall(Kora.sql.update, "UPDATE `kora_mdt_bolos` SET `status` = 'resolved' WHERE `subject_type` = 'vehicle' AND `subject_identifier` = ? AND `status` = 'active'", { plate })
    if not ok then mdtWarn('resolve', changed); return 0 end
    return tonumber(changed) or 0
end

---@param officerSrc integer
---@param plate string
---@param reason string|nil
---@return boolean, string|nil
function Police.flagPlate(officerSrc, plate, reason)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    plate = normalizePlate(plate)
    if not plate then return false, 'invalid plate' end
    if type(reason) ~= 'string' or reason:match('^%s*$') then reason = 'BOLO' end
    Police.plateFlags[plate] = { reason = reason, flaggedBy = officerSrc, flaggedAt = os.time() }
    mdtFlag(officerSrc, plate, reason)
    return true
end

---@param officerSrc integer
---@param plate string
---@return boolean, string|nil
function Police.unflagPlate(officerSrc, plate)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    plate = normalizePlate(plate)
    if not plate then return false, 'invalid plate' end
    -- Flags live in memory, so one set before a restart (or raised in the MDT
    -- itself) is only still known to the MDT: closing it there counts too.
    local resolved = mdtUnflag(plate)
    if not Police.plateFlags[plate] and resolved == 0 then return false, 'plate is not flagged' end
    Police.plateFlags[plate] = nil
    return true
end

---@param plate string
---@return boolean flagged, table|nil entry
function Police.isPlateFlagged(plate)
    plate = normalizePlate(plate)
    if not plate then return false end
    local entry = Police.plateFlags[plate]
    return entry ~= nil, entry
end

---Called by a police client that spotted a flagged plate nearby (a patrol
---HUD/ALPR-style feature -- client/dispatch.lua polls this, not built here).
---@param spotterSrc integer
---@param plate string
function Police.triggerFlaggedPlate(spotterSrc, plate)
    local flagged, entry = Police.isPlateFlagged(plate)
    if not flagged then return end
    for _, src in ipairs(exports.kora_core:getPlayersByJob(Config.police.job, true)) do
        TriggerClientEvent('kora_police:client:flaggedPlateTriggered', src, plate, entry.reason)
        TriggerClientEvent('police:client:FlaggedPlateTriggered', src, plate, entry.reason)
    end
end

---Stock `police:server:FlaggedPlateTriggered(coords, plate)`. Stock fans the
---plate out to every officer unchecked; here the sender must be an on-duty
---officer and the plate must really be flagged, so Police.triggerFlaggedPlate
---(and its own flag lookup) stays the only path to an alert. `coords` is ignored:
---it is client-supplied and no kora alert uses it. Also accepts the older kora
---`(plate)` form.
---@param spotterSrc integer
---@param first any coords (stock) or plate (older kora form)
---@param second any plate (stock)
---@return boolean, string|nil
function Police.legacyFlaggedPlate(spotterSrc, first, second)
    local plate = second
    if type(plate) ~= 'string' and type(first) == 'string' then plate = first end
    if type(plate) ~= 'string' or #plate == 0 or #plate > 16 then return false, 'invalid plate' end
    if not Police.isPolice(spotterSrc) then return false, 'not an on-duty officer' end
    Police.triggerFlaggedPlate(spotterSrc, plate:upper())
    return true
end

RegisterNetEvent('kora_police:server:flagPlate', function(plate, reason)
    local ok, err = Police.flagPlate(source, plate, reason)
    if ok then
        Police.notify(source, 'Plate flagged.', 'success')
    else
        Police.notify(source, err)
    end
end)
RegisterNetEvent('kora_police:server:unflagPlate', function(plate)
    local ok, err = Police.unflagPlate(source, plate)
    if ok then
        Police.notify(source, 'Plate unflagged.', 'success')
    else
        Police.notify(source, err)
    end
end)
RegisterNetEvent('kora_police:server:plateSpotted', function(plate)
    Police.triggerFlaggedPlate(source, plate)
end)

Kora.callback.register('kora_police:server:isPlateFlagged', function(src, plate)
    return Police.isPlateFlagged(plate)
end)
