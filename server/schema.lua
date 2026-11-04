QBPoliceSchema = {
    {
        name = 'kora_police_ballistic_casings',
        columns = {
            { name = 'case_id', type = 'varchar(64)' },
            { name = 'round_id', type = 'varchar(96)' },
            { name = 'weapon_serial', type = 'varchar(96)' },
            { name = 'weapon_name', type = 'varchar(96)' },
            { name = 'ammo_type', type = 'varchar(64)', null = true, default = Kora.sql.NULL },
            { name = 'lot', type = 'varchar(64)', null = true, default = Kora.sql.NULL },
            { name = 'x', type = 'double' },
            { name = 'y', type = 'double' },
            { name = 'z', type = 'double' },
            { name = 'bucket', type = 'int', default = 0 },
            { name = 'created_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
            { name = 'collected_by', type = 'varchar(64)', null = true, default = Kora.sql.NULL },
            { name = 'collected_at', type = 'timestamp', null = true, default = Kora.sql.NULL },
        },
        primary = { 'case_id' },
        indexes = {
            { name = 'idx_ballistic_serial', columns = { 'weapon_serial' } },
            { name = 'idx_ballistic_collected', columns = { 'collected_at' } },
        },
    },
}
