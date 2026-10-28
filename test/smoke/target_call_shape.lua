-- Source-level guardrail for kora_target call shapes. kora_target's NATIVE
-- entity/model/globalType API takes the options ARRAY positionally --
-- addGlobalType(entityType, { {label=...}, ... }, distance) -- while the
-- legacy qb-target envelope ({ options = {...}, distance = n }) is only
-- unwrapped by kora_target's qb-target compat identity. The concrete native
-- calls live in Police.target's shared wrappers, so every police interaction
-- gets the correct shape and restart-safe ownership behaviour. The zone APIs
-- (addBoxZone/addSphereZone/addPolyZone) DO take a single opts object with
-- an `options` key -- those are correct and unaffected here.
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

h.test('the shared target wrapper owns the native addGlobalType call', function()
    local hits = 0
    for _, path in ipairs(lfs_files) do
        local ok, src = pcall(source, path)
        if ok then
            for _ in src:gmatch(':addGlobalType%(') do hits = hits + 1 end
        end
    end
    h.assertEqual(hits, 1, ('expected one shared addGlobalType call site, found %d'):format(hits))
end)

h.test('every police blip caller uses qblib canonical category/name fields', function()
    local duty = source('config.lua')
    local evidence = source('client/evidence.lua')
    local tracker = source('client/tracker.lua')
    h.assertTrue(duty:find("category = 'Police'", 1, true) ~= nil, 'stations use Police')
    h.assertTrue(evidence:find("category = 'Evidence'", 1, true) ~= nil, 'evidence uses Evidence')
    h.assertTrue(evidence:find('name = evType', 1, true) ~= nil, 'evidence type is the marker name')
    h.assertTrue(tracker:find("category = 'Vehicle Tracking'", 1, true) ~= nil, 'trackers use Vehicle Tracking')
    h.assertTrue(tracker:find('name = tostring(targetServerId)', 1, true) ~= nil, 'tracker id is the marker name')
end)

h.report('target_call_shape')
