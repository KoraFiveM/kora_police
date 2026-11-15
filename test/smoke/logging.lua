-- Migrated diagnostics: a failing dispatch alert registration must reach Kora.logging.error
-- with a stable event name and the error in fields (not print, not interpolated into the message).
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')

local calls = {}
local function spy(level)
    return function(event, message, fields) calls[#calls + 1] = { level = level, event = event, message = message, fields = fields }; return true end
end
_G.Kora.logging = _G.Kora.logging or {}
for _, level in ipairs({ 'trace', 'debug', 'info', 'warn', 'error', 'fatal' }) do _G.Kora.logging[level] = spy(level) end
_G.Kora.logging.isEnabled = function() return true end

local rawPrints = 0
local realPrint = print
_G.print = function(...) rawPrints = rawPrints + 1 end

local baseExports = _G.exports
_G.exports = setmetatable({ kora_dispatch = { registerPlayerAlert = function() return false, 'dispatch offline' end } },
    { __index = function(_, name) return baseExports[name] end })
dofile('server/dispatch.lua')
_G.print = realPrint

h.test('a failed dispatch alert registration is logged as an error with the error in fields', function()
    local found
    for _, c in ipairs(calls) do if c.event == 'dispatch.alert_register_failed' then found = c; break end end
    h.assertTrue(found ~= nil, 'logger was called')
    h.assertEqual(found.level, 'error', 'severity')
    h.assertEqual(found.fields.error, 'dispatch offline', 'error carried in fields')
    h.assertTrue(not found.message:find('dispatch offline', 1, true), 'message stays static')
    h.assertEqual(rawPrints, 0, 'no raw print')
end)

h.report('logging')
