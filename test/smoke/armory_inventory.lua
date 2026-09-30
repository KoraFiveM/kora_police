-- Exercise qbpolice's registration through the sibling qbinventory authority,
-- rather than replacing its open, purchase or session validation with mocks.
-- Run from qbpolice; pass an alternate armory file for the pre-fix control.
local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install()
dofile('config.lua')
dofile('../qbinventory/config.lua')

local core = handle.exportImpls.qbcore
local definitions = { items = {}, weapons = {} }
dofile('../qbcore/shared/items.lua')
dofile('../qbcore/shared/weapons.lua')
for kind, records in pairs({ items = QBCoreSeed.items, weapons = QBCoreSeed.weapons }) do
    for _, item in ipairs(records) do definitions[kind][item.name] = item end
end
function core.getShared(kind, name) return definitions[kind] and definitions[kind][name] end
function core.registerShared(kind, name, item) definitions[kind][name] = item; return true end
function core.setPath(src, path, value)
    h.assertEqual(path[1], 'items')
    local data = handle.players[src].data
    for index = 1, #path - 1 do data = data[path[index]] end
    data[path[#path]] = value
    TriggerEvent('qbcore:server:inventoryChanged', src, path, value)
    return true
end
dofile('server/items.lua')

QB.util.isInteger = function(value) return QB.util.isFiniteNumber(value) and value % 1 == 0 end
QB.distance = {}
dofile('../qblib/modules/distancecheck/server.lua')
-- The unused useable-item ownership registry needs no external resource here.
QB.resources = { serverRegistry = function() return { track = function() end } end }
dofile('../qbinventory/shared.lua')
dofile('../qbinventory/server.lua')
local api, internal = QbInventory.api, QbInventory.internal
for name, fn in pairs(api) do handle.exportImpls.qbinventory[name] = fn end

-- Model the callable table and fresh coroutine of a cross-resource function
-- reference on re-registration, without changing the callback's player data.
local transported, callbackCalls = false, 0
function handle.exportImpls.qbinventory.RegisterShop(id, opts)
    if transported and opts.access then
        local access = opts.access
        opts.access = setmetatable({}, { __call = function(_, ...)
            local thread = coroutine.create(access)
            local result = table.pack(coroutine.resume(thread, ...))
            assert(result[1], result[2])
            assert(coroutine.status(thread) == 'dead', 'access callback must not wait')
            callbackCalls = callbackCalls + 1
            return table.unpack(result, 2, result.n)
        end })
    end
    return api.RegisterShop(id, opts)
end
dofile('server/core.lua')
dofile(arg[1] or 'server/armory.lua')

local patrol, sergeant, swat = table.unpack(Config.armory.shops)
local open = QB.callback.registry['qbinventory:server:open']
local intent = QB.callback.registry['qbinventory:server:intent']
local nextSource = 0
local function officer(shop, grade, onDuty, job)
    nextSource = nextSource + 1
    handle.addPlayer(nextSource, {
        coords = vector3(shop.coords.x, shop.coords.y, shop.coords.z),
        job = { name = job or Config.police.job, onduty = onDuty ~= false, grade = { level = grade or 5 } },
        money = { cash = 3000, bank = 5000 },
    })
    local player = handle.players[nextSource]
    player.data.job, player.data.items = player.job, {}
    return nextSource
end
local function shopInventory(shop) return internal.getInventory('shop:' .. shop.id) end
local function snapshot(src, shop, slot)
    local inv = shopInventory(shop)
    return {
        items = handle.players[src].data.items,
        count = api.getItemCount(src, shop.items[slot].name),
        cash = core.getMoney(src, 'cash'),
        stock = inv.stock[slot].amount,
        shopRevision = internal.getRevision(inv.key),
        playerRevision = internal.getRevision('player:' .. src),
    }
end
local function unchanged(src, shop, slot, before)
    local after = snapshot(src, shop, slot)
    for field, value in pairs(before) do h.assertEqual(after[field], value, field .. ' changed on rejection') end
end
local function refuseDirect(src, shop, slot)
    local before = snapshot(src, shop, slot)
    h.assertFalse(open(src, 'shop', shop.id), 'direct inventory open must be denied')
    h.assertFalse(exports.qbinventory:buyItem(src, shop.id, slot, 1), 'direct shop purchase must be denied')
    unchanged(src, shop, slot, before)
end
local function openedRequest(src, shop, slot)
    local ok, opened = open(src, 'shop', shop.id)
    h.assertTrue(ok, opened)
    return {
        action = 'buy', token = opened.token,
        primaryRevision = opened.primary.revision,
        secondaryRevision = opened.secondary.revision,
        payload = { inventory = opened.secondary.key, slot = slot, amount = 1 },
    }
end

h.test('direct inventory opens and purchases deny off-duty officers', function()
    refuseDirect(officer(sergeant, 5, false), sergeant, 3)
end)

h.test('direct inventory opens and purchases deny remote officers', function()
    local src = officer(sergeant)
    handle.setCoords(src, sergeant.coords.x + sergeant.distance + 0.1, sergeant.coords.y, sergeant.coords.z)
    refuseDirect(src, sergeant, 3)
end)

h.test('direct inventory opens and purchases retain grade and job restrictions', function()
    refuseDirect(officer(sergeant, 1), sergeant, 3)
    refuseDirect(officer(sergeant, 5, true, 'unemployed'), sergeant, 3)
end)

h.test('nearby on-duty purchase uses configured stock and cash price', function()
    local src = officer(sergeant, sergeant.minGrade)
    local before = snapshot(src, sergeant, 3)
    h.assertTrue(exports.qbinventory:buyItem(src, sergeant.id, 3, 1))
    h.assertEqual(api.getItemCount(src, 'shotgun_ammo'), before.count + 1)
    h.assertEqual(core.getMoney(src, 'cash'), before.cash - sergeant.items[3].price)
    h.assertEqual(shopInventory(sergeant).stock[3].amount, before.stock - 1)
end)

h.test('patrol purchase remains free for its own minimum grade', function()
    local src = officer(patrol, patrol.minGrade)
    local before = snapshot(src, patrol, 3)
    h.assertTrue(exports.qbinventory:buyItem(src, patrol.id, 3, 1))
    h.assertEqual(api.getItemCount(src, 'handcuffs'), before.count + 1)
    h.assertEqual(core.getMoney(src, 'cash'), before.cash)
    h.assertEqual(shopInventory(patrol).stock[3].amount, before.stock - 1)
end)

h.test('an open lease cannot purchase after the officer goes off duty', function()
    local src = officer(sergeant)
    local request = openedRequest(src, sergeant, 3)
    local before = snapshot(src, sergeant, 3)
    handle.players[src].job.onduty = false
    h.assertFalse(intent(src, request))
    h.assertEqual(internal.sessionOf(src), nil, 'denied lease is closed')
    unchanged(src, sergeant, 3, before)
end)

h.test('an open lease cannot purchase after the officer leaves the room', function()
    local src = officer(sergeant)
    local request = openedRequest(src, sergeant, 3)
    local before = snapshot(src, sergeant, 3)
    handle.setCoords(src, sergeant.coords.x + 20, sergeant.coords.y, sergeant.coords.z)
    h.assertFalse(intent(src, request))
    h.assertEqual(internal.sessionOf(src), nil)
    unchanged(src, sergeant, 3, before)
end)

h.test('an open lease retains the live grade check', function()
    local src = officer(sergeant)
    local request = openedRequest(src, sergeant, 3)
    local before = snapshot(src, sergeant, 3)
    handle.players[src].job.grade.level = sergeant.minGrade - 1
    h.assertFalse(intent(src, request))
    unchanged(src, sergeant, 3, before)
end)

h.test('a valid inventory lease buys through the actual intent authority', function()
    local src = officer(sergeant)
    local request = openedRequest(src, sergeant, 3)
    local before = snapshot(src, sergeant, 3)
    h.assertTrue(intent(src, request))
    h.assertEqual(api.getItemCount(src, 'shotgun_ammo'), before.count + 1)
    h.assertEqual(core.getMoney(src, 'cash'), before.cash - sergeant.items[3].price)
    h.assertEqual(shopInventory(sergeant).stock[3].amount, before.stock - 1)
end)

h.test('inventory re-registration preserves stock and binds each room access callback', function()
    local stocks = {}
    for _, shop in ipairs(Config.armory.shops) do
        stocks[shop.id] = shopInventory(shop).stock[1].amount
    end
    local paidStock = shopInventory(sergeant).stock[3].amount
    transported = true
    handle.fireEvent('onResourceStart', nil, 'qbinventory')
    for _, shop in ipairs(Config.armory.shops) do
        h.assertEqual(shopInventory(shop).stock[1].amount, stocks[shop.id])
        h.assertEqual(shopInventory(shop).currency, 'money')
        h.assertTrue(open(officer(shop, shop.minGrade), 'shop', shop.id), shop.id)
        refuseDirect(officer(shop, 5, false), shop, 1)
    end
    h.assertEqual(shopInventory(sergeant).stock[3].amount, paidStock, 'spent stock is not reset')
    local src = officer(swat, swat.minGrade)
    h.assertTrue(exports.qbinventory:buyItem(src, swat.id, 2, 1))
    h.assertEqual(api.getItemCount(src, 'rifle_ammo'), 1)
    h.assertTrue(callbackCalls > 0, 'callable cross-resource callbacks ran in fresh coroutines')
end)

h.report('armory_inventory')
