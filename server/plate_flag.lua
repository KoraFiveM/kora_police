-- Plate flags (BOLO/stolen/wanted) -- a small in-memory registry an officer
-- can add/remove from, checked automatically whenever a vehicle spawns
-- nearby a patrol car (client/dispatch.lua polls `IsPlateFlagged`), firing
-- the legacy `FlaggedPlateTriggered` event at the flagging officer's job.

---@param officerSrc integer
---@param plate string
---@param reason string|nil
---@return boolean, string|nil
function Police.flagPlate(officerSrc, plate, reason)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if type(plate) ~= 'string' or plate == '' then return false, 'invalid plate' end
    plate = plate:upper()
    Police.plateFlags[plate] = { reason = reason or 'BOLO', flaggedBy = officerSrc, flaggedAt = os.time() }
    return true
end

---@param officerSrc integer
---@param plate string
---@return boolean, string|nil
function Police.unflagPlate(officerSrc, plate)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if type(plate) ~= 'string' then return false, 'invalid plate' end
    plate = plate:upper()
    if not Police.plateFlags[plate] then return false, 'plate is not flagged' end
    Police.plateFlags[plate] = nil
    return true
end

---@param plate string
---@return boolean flagged, table|nil entry
function Police.isPlateFlagged(plate)
    if type(plate) ~= 'string' then return false end
    local entry = Police.plateFlags[plate:upper()]
    return entry ~= nil, entry
end

---Called by a police client that spotted a flagged plate nearby (a patrol
---HUD/ALPR-style feature -- client/dispatch.lua polls this, not built here).
---@param spotterSrc integer
---@param plate string
function Police.triggerFlaggedPlate(spotterSrc, plate)
    local flagged, entry = Police.isPlateFlagged(plate)
    if not flagged then return end
    for _, src in ipairs(exports.qbcore:getPlayersByJob(Config.police.job, true)) do
        TriggerClientEvent('qbpolice:client:flaggedPlateTriggered', src, plate, entry.reason)
        TriggerClientEvent('police:client:FlaggedPlateTriggered', src, plate, entry.reason)
    end
end

RegisterNetEvent('qbpolice:server:flagPlate', function(plate, reason)
    local ok, err = Police.flagPlate(source, plate, reason)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:unflagPlate', function(plate)
    local ok, err = Police.unflagPlate(source, plate)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:plateSpotted', function(plate)
    Police.triggerFlaggedPlate(source, plate)
end)

QB.callback.register('qbpolice:server:isPlateFlagged', function(src, plate)
    return Police.isPlateFlagged(plate)
end)
