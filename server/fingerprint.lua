-- Deterministic per-citizen fingerprint id, revealed to police via search
-- (`showFingerprint`/`showFingerprintId` legacy compat). Generated once per
-- citizenid and cached for the life of the server process -- no schema
-- change, no persistence needed beyond that (matches how qb-policejob's own
-- fingerprint ids are throwaway session data, not a durable record).

local CHARS = '0123456789'

---@param citizenId string
---@return string
function Police.getFingerprint(citizenId)
    if Police.fingerprints[citizenId] then return Police.fingerprints[citizenId] end
    local id = {}
    for i = 1, 10 do
        local pick = math.random(1, #CHARS)
        id[i] = CHARS:sub(pick, pick)
    end
    local fingerprint = table.concat(id)
    Police.fingerprints[citizenId] = fingerprint
    return fingerprint
end

---@param officerSrc integer
---@param targetSrc integer
---@return string|nil fingerprint
function Police.getFingerprintForOfficer(officerSrc, targetSrc)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not Police.isPolice(officerSrc) then return nil end
    if not Police.isCuffed(targetSrc) then return nil end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return nil end

    local cid = Police.citizenId(targetSrc)
    if not cid then return nil end
    return Police.getFingerprint(cid)
end

Kora.callback.register('qbpolice:server:getFingerprint', function(src, target)
    return Police.getFingerprintForOfficer(src, target)
end)
