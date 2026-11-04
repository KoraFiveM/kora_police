-- Ballistics schema is declared for kora_sql and applied through ensureTables.
local h = dofile('test/harness.lua')

local captured, threads = nil, {}
_G.Kora = { sql = {
    NULL = {},
    ready = function() return true end,
    ensureTables = function(specs) captured = specs; return { { table = specs[1].name, warnings = { 'w' } } }, nil end,
} }
_G.CreateThread = function(fn) threads[#threads + 1] = fn end

dofile('server/schema.lua')
dofile('server/migrate.lua')
for _, fn in ipairs(threads) do fn() end

h.test('schema declares the ballistic casings table', function()
    local spec = QBPoliceSchema[1]
    h.assertEqual(spec.name, 'kora_police_ballistic_casings')
    h.assertEqual(spec.primary[1], 'case_id')
    h.assertEqual(#spec.columns, 13)
    h.assertEqual(#spec.indexes, 2)
end)

h.test('migrate applies the schema via ensureTables', function()
    h.assertTrue(captured == QBPoliceSchema)
end)

h.report('schema')
