-- Durable ballistic evidence.  The current resource owns the operational
-- casing record; an MDT may read it only through its authorised exports.

local function fnv1a(value)
    local hash, prime = 0xCBF29CE484222325, 0x100000001B3
    for i = 1, #value do hash = (hash ~ string.byte(value, i)) * prime & 0xFFFFFFFFFFFFFFFF end
    return hash
end

local function checksum(value)
    return ('%016x%016x'):format(fnv1a(value), fnv1a(value:reverse())) .. string.rep('0', 32)
end

CreateThread(function()
    if not QB.sql.ready(60000) then
        print('^1[qbpolice:ballistics]^7 qbsql was unavailable; ballistic evidence is disabled until restart.')
        return
    end
    local resource, file = GetCurrentResourceName(), 'sql/001_ballistics.sql'
    local sql = LoadResourceFile(resource, file)
    if not sql then print('^1[qbpolice:ballistics]^7 missing migration ' .. file); return end
    local _, err = QB.sql.migrate(resource, {
        { version = 1, name = 'ballistics', sql = sql, checksum = checksum(sql) },
    })
    if err then print(('^1[qbpolice:ballistics]^7 migration failed: %s'):format(tostring(err))) end
end)
