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

h.report('armory')
