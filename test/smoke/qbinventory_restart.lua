-- Proves that a kora_inventory restart actually triggers RE-registration of
-- the server-side kora_inventory shop/stash objects kora_police owns (the armory
-- rooms in server/armory.lua, the evidence locker in server/evidence.lua),
-- not just that a wrapper function exists. A `dependency 'kora_inventory'`
-- declaration only guarantees kora_inventory is running before kora_police's own
-- scripts start on a FRESH BOOT -- it says nothing about a later kora_inventory
-- RESTART mid-session, which wipes kora_inventory's own shop/stash tables
-- without kora_police itself restarting. Mirrors test/smoke/target_restart.lua,
-- which proves the equivalent client-side qbtarget-restart safety.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('server/core.lua')

local qbinventory = handle.exportImpls.kora_inventory
local shopCalls, stashCalls = 0, 0
function qbinventory.RegisterShop(...) shopCalls = shopCalls + 1; return 'shop:mock' end
function qbinventory.RegisterStash(...) stashCalls = stashCalls + 1; return 'stash:mock' end

dofile('server/armory.lua')
dofile('server/evidence.lua')

h.test('armory shops and the evidence locker are registered once at load', function()
    h.assertTrue(shopCalls >= #Config.armory.shops, 'expected one RegisterShop call per configured armory room')
    h.assertEqual(stashCalls, 1, 'expected exactly one RegisterStash call for the evidence locker')
end)

local shopsAfterLoad, stashAfterLoad = shopCalls, stashCalls

h.test('firing onResourceStart for qbinventory re-registers both the armory shops and the evidence locker', function()
    handle.fireEvent('onResourceStart', nil, 'kora_inventory')

    h.assertEqual(shopCalls, shopsAfterLoad * 2,
        ('expected RegisterShop call count to exactly double after a simulated qbinventory restart (was %d, got %d)')
            :format(shopsAfterLoad, shopCalls))
    h.assertEqual(stashCalls, stashAfterLoad * 2,
        ('expected RegisterStash call count to exactly double after a simulated qbinventory restart (was %d, got %d)')
            :format(stashAfterLoad, stashCalls))
end)

h.test('firing onResourceStart for an unrelated resource does not re-register anything', function()
    local shopsBefore, stashBefore = shopCalls, stashCalls
    handle.fireEvent('onResourceStart', nil, 'some-other-resource')
    h.assertEqual(shopCalls, shopsBefore, 'onResourceStart for a non-qbinventory resource must be a no-op for armory')
    h.assertEqual(stashCalls, stashBefore, 'onResourceStart for a non-qbinventory resource must be a no-op for evidence')
end)

h.report('qbinventory_restart')
