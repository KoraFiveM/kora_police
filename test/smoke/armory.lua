-- Police.canAccessArmory -- job/on-duty, grade, and distance gating for the
-- fresh armory build (kora_inventory's RegisterShop is mocked; this only tests
-- kora_police's own access decision, not kora_inventory's shop mechanics).
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')
dofile('server/armory.lua')

local CADET, SERGEANT, CHIEF, CIVILIAN = 1, 2, 3, 4
local patrol, sergeantArmory = Config.armory.shops[1], Config.armory.shops[2]
h.assertEqual(patrol.id, 'pd-armory-patrol')
h.assertEqual(sergeantArmory.id, 'pd-armory-sergeant')

handle.addPlayer(CADET, { coords = handle.vec3(patrol.coords.x, patrol.coords.y, patrol.coords.z), job = { name = 'police', onduty = true, grade = { level = 1 } } })
handle.addPlayer(SERGEANT, { coords = handle.vec3(patrol.coords.x, patrol.coords.y, patrol.coords.z), job = { name = 'police', onduty = true, grade = { level = 3 } } })
handle.addPlayer(CHIEF, { coords = handle.vec3(patrol.coords.x, patrol.coords.y, patrol.coords.z), job = { name = 'police', onduty = true, grade = { level = 5 } } })
handle.addPlayer(CIVILIAN, { coords = handle.vec3(patrol.coords.x, patrol.coords.y, patrol.coords.z), job = { name = 'unemployed', onduty = false, grade = { level = 1 } } })

h.test('every registered shop is tracked after boot', function()
    for _, shop in ipairs(Config.armory.shops) do
        h.assertTrue(Police.armoryShops[shop.id] ~= nil, shop.id .. ' should be registered')
    end
end)

h.test('a cadet can access the patrol armory (minGrade 1)', function()
    local ok = Police.canAccessArmory(CADET, 'pd-armory-patrol')
    h.assertTrue(ok)
end)

h.test('a cadet cannot access the sergeant armory (minGrade 3)', function()
    local ok, err = Police.canAccessArmory(CADET, 'pd-armory-sergeant')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('a sergeant can access the sergeant armory', function()
    handle.setCoords(SERGEANT, sergeantArmory.coords.x, sergeantArmory.coords.y, sergeantArmory.coords.z)
    local ok = Police.canAccessArmory(SERGEANT, 'pd-armory-sergeant')
    h.assertTrue(ok)
    handle.setCoords(SERGEANT, patrol.coords.x, patrol.coords.y, patrol.coords.z)
end)

h.test('a sergeant cannot access the SWAT armory (minGrade 4)', function()
    local swat = Config.armory.shops[3]
    handle.setCoords(SERGEANT, swat.coords.x, swat.coords.y, swat.coords.z)
    local ok, err = Police.canAccessArmory(SERGEANT, 'pd-armory-swat')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    handle.setCoords(SERGEANT, patrol.coords.x, patrol.coords.y, patrol.coords.z)
end)

h.test('the chief (grade 5) can access every armory room', function()
    for _, shop in ipairs(Config.armory.shops) do
        handle.setCoords(CHIEF, shop.coords.x, shop.coords.y, shop.coords.z)
        h.assertTrue(Police.canAccessArmory(CHIEF, shop.id), shop.id .. ' should be reachable by the chief')
    end
    handle.setCoords(CHIEF, patrol.coords.x, patrol.coords.y, patrol.coords.z)
end)

h.test('a civilian cannot access any armory room regardless of grade', function()
    local ok, err = Police.canAccessArmory(CIVILIAN, 'pd-armory-patrol')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('an off-duty officer cannot access the armory', function()
    handle.players[CADET].job.onduty = false
    local ok, err = Police.canAccessArmory(CADET, 'pd-armory-patrol')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    handle.players[CADET].job.onduty = true
end)

h.test('an unknown shop id is refused', function()
    local ok, err = Police.canAccessArmory(CHIEF, 'no-such-shop')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
end)

h.test('a qualifying officer standing far from the room is refused', function()
    handle.setCoords(CHIEF, patrol.coords.x + 9999.0, patrol.coords.y, patrol.coords.z)
    local ok, err = Police.canAccessArmory(CHIEF, 'pd-armory-patrol')
    h.assertFalse(ok)
    h.assertTrue(err ~= nil)
    handle.setCoords(CHIEF, patrol.coords.x, patrol.coords.y, patrol.coords.z)
end)

h.test('the patrol armory issues the evidence bag needed to collect casings', function()
    local found = false
    for _, row in ipairs(patrol.items) do
        if row.name == Config.evidence.bagItem then found = true end
    end
    h.assertTrue(found, 'Config.evidence.bagItem is free-issue in the patrol armory')
end)

h.test('a saved armory gets new config items back and its free kit topped up', function()
    local inv = handle.exportImpls.kora_inventory
    -- Stock saved before the evidence bag was configured, the handcuffs since run out.
    local saved = {
        [1] = { name = patrol.items[1].name, amount = patrol.items[1].amount, price = 0 },
        [2] = { name = patrol.items[2].name, amount = patrol.items[2].amount, price = 0 },
        [3] = { name = 'handcuffs', amount = 0, price = 0 },
        [4] = { name = patrol.items[4].name, amount = patrol.items[4].amount, price = 0 },
        [5] = { name = patrol.items[5].name, amount = patrol.items[5].amount, price = 0 },
    }
    local written
    inv.GetShopItems = function(id) h.assertEqual(id, patrol.id); return saved end
    inv.SetShopItems = function(id, items) written = items; return true end

    h.assertTrue(Police.restockArmory(patrol), 'restocked')
    h.assertEqual(written[3].amount, patrol.items[3].amount, 'run-out kit topped up')
    h.assertEqual(written[6].name, Config.evidence.bagItem, 'new config item added to its slot')

    written = nil
    h.assertFalse(Police.restockArmory(patrol), 'nothing to do once full')
    h.assertEqual(written, nil)

    Config.armory.restockOnStart = false
    saved[6] = nil
    h.assertFalse(Police.restockArmory(patrol), 'off leaves saved stock alone')
    Config.armory.restockOnStart = true
    inv.GetShopItems, inv.SetShopItems = nil, nil
end)

h.test('on a server boot the restock waits until kora_inventory has loaded its saved shops', function()
    local inv = handle.exportImpls.kora_inventory
    -- kora_inventory hydrates saved shops after this resource registered them,
    -- replacing the registered stock: a restock before that is lost.
    local loaded, writes = false, 0
    local saved = { [3] = { name = 'handcuffs', amount = 3, price = 0 } }
    inv.getPersistenceStatus = function() return { enabled = true, ready = loaded } end
    inv.GetShopItems = function(id) return id == patrol.id and saved or {} end
    inv.SetShopItems = function(id, items)
        if id == patrol.id then writes, saved = writes + 1, items end
        return true
    end
    dofile('server/armory.lua')
    h.assertEqual(writes, 0, 'no restock before the saved shops are loaded')

    loaded = true
    TriggerEvent('qbinventory:server:ready', { ready = true })
    h.assertEqual(writes, 1, 'restocked once the saved shops are loaded')
    h.assertEqual(saved[3].amount, patrol.items[3].amount, 'run-out kit topped up')
    h.assertEqual(saved[#patrol.items].name, Config.evidence.bagItem, 'missing kit put back')

    TriggerEvent('qbinventory:server:ready', { ready = true })
    h.assertEqual(writes, 1, 'a later kora_inventory load (its restart) does not restock again')
    inv.getPersistenceStatus, inv.GetShopItems, inv.SetShopItems = nil, nil, nil
end)

h.report('armory')
