-- Durable ballistic evidence.  The current resource owns the operational
-- casing record; an MDT may read it only through its authorised exports.

CreateThread(function()
    if not Kora.sql.ready(60000) then
        Kora.logging.error('ballistics.sql_unavailable', 'kora_sql was unavailable; ballistic evidence is disabled until restart')
        return
    end
    local reports, err = Kora.sql.ensureTables(KoraPoliceSchema)
    if err then
        Kora.logging.error('ballistics.schema_failed', 'Ballistic evidence schema setup failed', { error = tostring(err) })
        return
    end
    for _, report in ipairs(reports or {}) do
        for _, warning in ipairs(report.warnings or {}) do
            Kora.logging.warn('ballistics.schema_warning', 'Ballistic evidence schema warning', { table = tostring(report.table), warning = tostring(warning) })
        end
    end
end)
