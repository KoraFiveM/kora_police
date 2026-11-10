-- Durable ballistic evidence.  The current resource owns the operational
-- casing record; an MDT may read it only through its authorised exports.

CreateThread(function()
    if not Kora.sql.ready(60000) then
        print('^1[kora_police:ballistics]^7 kora_sql was unavailable; ballistic evidence is disabled until restart.')
        return
    end
    local reports, err = Kora.sql.ensureTables(KoraPoliceSchema)
    if err then
        print(('^1[kora_police:ballistics]^7 schema failed: %s'):format(tostring(err)))
        return
    end
    for _, report in ipairs(reports or {}) do
        for _, warning in ipairs(report.warnings or {}) do
            print(('^3[kora_police:ballistics]^7 %s: %s'):format(tostring(report.table), tostring(warning)))
        end
    end
end)
