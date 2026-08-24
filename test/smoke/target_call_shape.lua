-- Source-level guardrail for qbtarget call shapes. qbtarget's NATIVE
-- entity/model/globalType API takes the options ARRAY positionally --
-- addGlobalType(entityType, { {label=...}, ... }, distance) -- while the
-- legacy qb-target envelope ({ options = {...}, distance = n }) is only
-- unwrapped by qbtarget's qb-target compat identity. qbpolice shipped 13
-- registrations using the envelope against the native export; every one
-- failed validation ("options must be a non-empty array of target options")
-- at first client connect. The zone APIs (addBoxZone/addSphereZone/
-- addPolyZone) DO take a single opts object with an `options` key -- those
-- are correct and unaffected here.
local h = dofile('test/harness.lua')

local function source(path)
    local file = assert(io.open(path, 'r'))
    local value = file:read('*a')
    file:close()
    return value
end

local lfs_files = {
    'client/bill.lua', 'client/cuff.lua', 'client/duty.lua', 'client/escort.lua',
    'client/fingerprint.lua', 'client/impound.lua', 'client/jail.lua',
    'client/plate_flag.lua', 'client/rob.lua', 'client/search.lua',
    'client/seize.lua', 'client/tracker.lua', 'client/vehicle.lua',
    'client/armory.lua', 'client/evidence.lua', 'client/breach_minigame.lua',
    'client/spikes.lua', 'client/core.lua', 'client/dispatch.lua',
}

h.test('no addGlobalType/addModel/addEntity call passes a { options = ... } envelope', function()
    for _, path in ipairs(lfs_files) do
        local ok, src = pcall(source, path)
        if ok then
            -- For each positional-API call, the text between the opening
            -- paren and the first '{' plus the immediately following line
            -- must not introduce an `options =` key.
            for api in ('addGlobalType addModel addEntity'):gmatch('%S+') do
                local searchFrom = 1
                while true do
                    local s = src:find(':' .. api .. '%(', searchFrom)
                    if not s then break end
                    -- window: 120 chars after the call opener is more than
                    -- enough to cover the second argument's opening lines
                    local window = src:sub(s, s + 120)
                    h.assertTrue(window:find('options%s*=') == nil,
                        ('%s: %s must take the options array positionally, not a { options = ... } envelope')
                            :format(path, api))
                    searchFrom = s + 1
                end
            end
        end
    end
end)

h.test('addGlobalType call sites still exist (guard is exercising real code)', function()
    local hits = 0
    for _, path in ipairs(lfs_files) do
        local ok, src = pcall(source, path)
        if ok then
            for _ in src:gmatch(':addGlobalType%(') do hits = hits + 1 end
        end
    end
    h.assertTrue(hits >= 13, ('expected at least 13 addGlobalType call sites, found %d'):format(hits))
end)

h.report('target_call_shape')
