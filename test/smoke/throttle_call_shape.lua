-- Source-level guardrail for QB.timers.throttle/debounce handles.
--
-- qblib returns a callable TABLE whose `__call` metamethod does not survive the
-- export boundary: qbpolice reaches QB.timers through the qblib export proxy, so
-- the handle arrives here as a plain table and calling it directly raised
--   @qbpolice/client/detectors.lua:117: attempt to call a table value (upvalue 'reportMelee')
-- which killed the whole detector thread on the first melee fight. Every handle
-- must therefore be invoked as `handle.run(...)`.
--
-- This is a source check rather than a behavioural one because the failure is a
-- runtime call shape, and the previous test mock (`throttle = function(fn) return fn end`)
-- returned a bare function, which made the broken shape pass. The mock is now
-- shaped like the real handle, but a source guard also catches a new call site
-- added inside a branch no test happens to exercise.
local h = dofile('test/harness.lua')

---Reads a file with its line comments stripped. Comments matter here because
---the explanation of this very bug quotes the broken form (`reportMelee()`) in
---prose right above the fixed call, which a naive text search reads as a real
---call site.
---@param path string
---@return string
local function source(path)
    local file = assert(io.open(path, 'r'))
    local value = file:read('*a')
    file:close()

    return (value:gsub('%-%-[^\n]*', ''))
end

local files = {
    'client/detectors.lua', 'client/core.lua', 'client/dispatch.lua',
    'client/plate_flag.lua', 'client/spikes.lua', 'client/tracker.lua',
    'server/dispatch.lua',
}

h.test('every QB.timers.throttle/debounce handle is invoked through .run', function()
    local checked = 0

    for _, path in ipairs(files) do
        local ok, src = pcall(source, path)
        if ok then
            -- Collect the local name each throttle/debounce handle is bound to,
            -- then assert no bare `name(` call exists anywhere in the file.
            for name in src:gmatch('local%s+([%w_]+)%s*=%s*QB%.timers%.throttle') do
                checked = checked + 1
                h.assertTrue(src:find(name .. '%s*%(') == nil,
                    ('%s: %s is a throttle handle -- call %s.run(...), not %s(...)')
                        :format(path, name, name, name))
            end

            for name in src:gmatch('local%s+([%w_]+)%s*=%s*QB%.timers%.debounce') do
                checked = checked + 1
                h.assertTrue(src:find(name .. '%s*%(') == nil,
                    ('%s: %s is a debounce handle -- call %s.run(...), not %s(...)')
                        :format(path, name, name, name))
            end
        end
    end

    h.assertTrue(checked > 0, 'found no throttle/debounce handles -- this guard is not exercising real code')
end)

h.report('throttle_call_shape')
