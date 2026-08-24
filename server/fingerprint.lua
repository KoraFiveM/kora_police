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
    for i = 1, 10 do id[i] = CHARS:sub(math.random(1, #CHARS), math.random(1, #CHARS)) end
    local fingerprint = table.concat(id)
    Police.fingerprints[citizenId] = fingerprint
    return fingerprint
end

QB.callback.register('qbpolice:server:getFingerprint', function(src, target)
    local cid = Police.citizenId(target or src)
    if not cid then return nil end
    return Police.getFingerprint(cid)
end)
