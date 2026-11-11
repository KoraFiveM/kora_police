-- The resource owns marker state; dependency recorders enforce handle lifetime.
local h = dofile('test/harness.lua')
local mock = dofile('test/mocks.lua').install()
local resource = arg[1] or '.'
Police, Config = nil, nil
dofile(resource .. '/config.lua')

local now, threads, clients, requests = 1000, {}, {}, {}
local buckets, missingPed, bags, filled = {}, {}, {}, {}
local allowRemove, allowAdd = true, true
GetGameTimer = function() return now end
GetPlayerRoutingBucket = function(src) return buckets[src] or 0 end
GetPlayerPed = function(src) return not missingPed[src] and mock.players[src] and src or 0 end
CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
Kora.sql = { execute = function() return 1 end }
mock.exportImpls.kora_inventory.RemoveItem = function(src, name)
    h.assertEqual(name, 'empty_evidence_bag')
    if not allowRemove or (bags[src] or 0) == 0 then return false, 'Missing bag' end
    bags[src] = bags[src] - 1
    return true
end
mock.exportImpls.kora_inventory.AddItem = function(src, name, _, _, info)
    if name == 'empty_evidence_bag' then bags[src] = (bags[src] or 0) + 1; return true end
    h.assertEqual(name, 'filled_evidence_bag')
    if not allowAdd then return false, 'Inventory full' end
    filled[#filled + 1] = { src = src, info = info }
    return true
end
for src = 1, 3 do
    mock.addPlayer(src, { job = { name = src == 3 and 'unemployed' or 'police', onduty = src ~= 3 } })
end
Config.evidence.createCooldown = 0
dofile(resource .. '/server/core.lua')
dofile(resource .. '/server/evidence.lua')
local sweep = threads[#threads]
local function resumeSweep()
    local ok, err = coroutine.resume(sweep)
    h.assertTrue(ok, err)
end
resumeSweep()

local function client(src)
    local env = {}; for key, value in pairs(_G) do env[key] = value end
    env.Police, env.Config = {}, {}
    local c = { targets = {}, blips = {}, notices = {}, handlers = {}, state = 'started', nextTarget = 0, nextBlip = 0 }
    local function addTarget(_, options)
        h.assertEqual(c.state, 'started', 'target exports are unavailable while stopped')
        c.nextTarget = c.nextTarget + 1
        c.targets[c.nextTarget] = options
        return c.nextTarget
    end
    env.GetResourceState = function(name) return name == 'kora_target' and c.state or 'started' end
    env.AddEventHandler = function(name, fn)
        c.handlers[name] = c.handlers[name] or {}; table.insert(c.handlers[name], fn)
    end
    env.RegisterNetEvent = env.AddEventHandler
    env.TriggerServerEvent = function(name, ...) requests[#requests + 1] = { src = src, name = name, args = table.pack(...) } end
    env.Kora = {
        notify = { send = function(payload) c.notices[#c.notices + 1] = payload end },
        blips = {
            create = function()
                c.nextBlip = c.nextBlip + 1; c.blips[c.nextBlip] = true; return c.nextBlip
            end,
            remove = function(id)
                h.assertTrue(c.blips[id], 'only a live owned blip may be removed'); c.blips[id] = nil; return true
            end,
        },
    }
    -- FiveM's export table must also accept exports(name, function).
    env.exports = setmetatable({
        kora_core = { getPlayerData = function() return mock.players[src].job end },
        kora_inventory = { openInventory = function() end },
        kora_target = {
            addBoxZone = addTarget, addSphereZone = addTarget,
            removeZone = function(_, id)
                h.assertEqual(c.state, 'started'); h.assertTrue(c.targets[id], 'stale zone ID'); c.targets[id] = nil; return true
            end,
        },
    }, { __call = function() end })
    env.Kora.compat = assert(loadfile(resource .. '/../kora_lib/compat/provider.lua', 't', env))()()
    assert(loadfile(resource .. '/config.lua', 't', env))()
    assert(loadfile(resource .. '/client/core.lua', 't', env))()
    assert(loadfile(resource .. '/client/evidence.lua', 't', env))()
    c.fire = function(name, ...) for _, fn in ipairs(c.handlers[name] or {}) do fn(...) end end
    c.stop = function()
        c.retiredTarget = c.nextTarget
        c.targets, c.nextTarget, c.state = {}, 0, 'stopped'
        c.fire('onClientResourceStop', 'kora_target')
    end
    c.start = function()
        c.state = 'started'
        local other
        -- Other consumers can acquire every old ID before police re-registers.
        for _ = 1, c.retiredTarget do
            other = addTarget(nil, { options = { { label = 'unrelated' } } })
        end
        c.fire('onClientResourceStart', 'kora_target')
        return other
    end
    clients[src] = c
    return c
end
local a, b = client(1), client(2)
local oldClientEvent = TriggerClientEvent
TriggerClientEvent = function(name, target, ...)
    oldClientEvent(name, target, ...)
    for src, c in pairs(clients) do if target == -1 or target == src then c.fire(name, ...) end end
end
Kora.notify.send = function(src, payload) clients[src].notices[#clients[src].notices + 1] = payload end
local function count(values) local n = 0; for _ in pairs(values) do n = n + 1 end; return n end
local function zones(c)
    local n = 0; for _, opts in pairs(c.targets) do if opts.options[1].label:find('Collect ', 1, true) then n = n + 1 end end; return n
end
local function success(c)
    local n = 0; for _, payload in ipairs(c.notices) do if payload.type == 'success' then n = n + 1 end end; return n
end
local function assertView(expected)
    for _, c in ipairs({ a, b }) do h.assertEqual(zones(c), expected); h.assertEqual(count(c.blips), expected) end
end
local function create(event)
    now = now + 1
    local id = Police.nextEvidenceId
    mock.fireEvent('evidence:server:' .. (event or 'CreateBloodDrop'), 3)
    h.assertTrue(Police.worldEvidence[id]); return id
end
local function collect(src, id) mock.fireEvent('evidence:server:AddToInventory', src, id) end
local function select(c)
    for _, opts in pairs(c.targets) do if opts.options[1].label:find('Collect ', 1, true) then opts.options[1].onSelect(); return end end
    error('No evidence target')
end
local function flush()
    local pending = requests; requests = {}
    for _, r in ipairs(pending) do mock.fireEvent(r.name, r.src, table.unpack(r.args, 1, r.args.n)) end
end

h.test('collection waits for authority and clears both observers, including a former officer', function()
    local id, before = create(), success(a)
    mock.players[2].job = { name = 'unemployed', onduty = false }
    select(a); h.assertEqual(success(a), before); assertView(1)
    flush(); h.assertEqual(Police.worldEvidence[id], nil); assertView(0)
    h.assertEqual(success(a), before + 1)
    h.assertEqual(Police.collectedEvidence.CID1[id], true)
    local removed = mock.clientEventsFor('kora_police:client:worldEvidenceRemoved')
    h.assertEqual(removed[#removed].target, -1)
    mock.players[2].job = { name = 'police', onduty = true }
end)

h.test('authority, bucket, distance and missing-ped rejections retain the marker', function()
    local id, before = create(), success(a)
    collect(3, id)
    mock.players[1].job.onduty = false; collect(1, id); mock.players[1].job.onduty = true
    buckets[1] = 1; collect(1, id); buckets[1] = 0
    mock.players[1].coords = vector3(100, 0, 0); collect(1, id); mock.players[1].coords = vector3(0, 0, 0)
    missingPed[1] = true; collect(1, id); missingPed[1] = nil
    collect(1, 'unknown'); h.assertTrue(Police.worldEvidence[id]); assertView(1)
    h.assertEqual(success(a), before)
    collect(1, tostring(id)); assertView(0)
end)

h.test('bag failures retain presentation; packaging succeeds once after the server accepts it', function()
    local id, before = Police.nextEvidenceId, success(a)
    local caseId = Police.createBallisticCasing(3, { id = 'round', weaponSerial = 'serial', weapon = 'weapon_pistol' })
    h.assertEqual(type(caseId), 'string')
    select(a); h.assertEqual(success(a), before); flush(); assertView(1)
    h.assertEqual(success(a), before)
    bags[1], allowRemove = 1, false; select(a); flush(); assertView(1); h.assertEqual(bags[1], 1)
    allowRemove, allowAdd = true, false; select(a); flush(); assertView(1)
    h.assertEqual(bags[1], 1, 'existing refund preserves the empty bag'); h.assertEqual(success(a), before)
    allowAdd = true; select(a); h.assertEqual(success(a), before); flush()
    assertView(0); h.assertEqual(Police.worldEvidence[id], nil); h.assertEqual(success(a), before + 1)
    h.assertEqual(#filled, 1); h.assertEqual(filled[1].info.caseId, caseId)
    collect(1, id); h.assertEqual(success(a), before + 1); h.assertEqual(#filled, 1)
end)

h.test('eviction, collection-time expiry and periodic expiry clear every observer', function()
    Config.evidence.maxWorldMarkers = 1
    local first, second = create('CreateFingerDrop'), create()
    h.assertEqual(Police.worldEvidence[first], nil); assertView(1)
    now = now + Config.evidence.worldMarkerTtl; collect(1, second)
    h.assertEqual(Police.worldEvidence[second], nil); assertView(0)
    local third = create('CreateCasing'); now = now + Config.evidence.worldMarkerTtl; resumeSweep()
    h.assertEqual(Police.worldEvidence[third], nil); assertView(0)
end)

h.test('duplicate events and provider restart preserve current handles without touching reused IDs', function()
    local id = create(); local marker = Police.worldEvidence[id]
    a.fire('kora_police:client:worldEvidenceCreated', id, marker.type, marker.coords); assertView(1)
    a.stop(); local other = a.start(); assertView(1)
    a.fire('onClientResourceStart', 'kora_target'); assertView(1)
    collect(1, id); assertView(0); h.assertTrue(a.targets[other])
    a.fire('kora_police:client:worldEvidenceRemoved', id); h.assertTrue(a.targets[other])
end)

h.test('creation and deletion while kora_target is down keep only live markers for its return', function()
    a.stop()
    local id = create('CreateFingerDrop'); h.assertEqual(zones(a), 0); h.assertEqual(count(a.blips), 1)
    collect(1, id); h.assertEqual(count(a.blips), 0)
    id = create(); local other = a.start(); assertView(1)
    collect(1, id); assertView(0); h.assertTrue(a.targets[other])
end)

h.report('world_evidence')
