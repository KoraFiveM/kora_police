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
    if not Kora.sql.ready(60000) then
        print('^1[qbpolice:ballistics]^7 qbsql was unavailable; ballistic evidence is disabled until restart.')
        return
    end
    local resource = GetCurrentResourceName()
    local _, err = Kora.sql.migrateFiles(resource, {
        { version = 1, name = 'ballistics', file = 'sql/001_ballistics.sql' },
    }, checksum)
    if err then print(('^1[qbpolice:ballistics]^7 migration failed: %s'):format(tostring(err))) end
end)
