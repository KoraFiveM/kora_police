-- Armour items: armor/armour/heavyarmor are registered usable, run a progress bar,
-- are server-validated, consume one item and apply the configured armour.
local h = dofile("test/harness.lua")
local mocks = dofile("test/mocks.lua"); local handle = mocks.install()
dofile("config.lua")
dofile("server/core.lua")

local useables, removed, armour, progressResult = {}, {}, 0, true
handle.exportImpls.kora_core.createUseable = function(name, cb) useables[name] = cb end
handle.exportImpls.kora_core.removeItem = function(_, name, amount, slot)
    removed[#removed + 1] = { name = name, amount = amount, slot = slot }
    return true
end
_G.GetPedArmour = function() return armour end
local progressCalls = {}
Kora.callback.trigger = function(_, name, payload)
    progressCalls[#progressCalls + 1] = { name = name, payload = payload }
    -- advance the clock past the configured duration like a real progress bar
    for _ = 1, payload.duration // 16 + 1 do GetGameTimer() end
    return progressResult
end
dofile("server/armour.lua")

handle.addPlayer(1, { job = { name = "police", onduty = true, grade = { level = 1 } } })

local function reset()
    removed, progressCalls, handle.clientEvents = {}, {}, handle.clientEvents
    armour, progressResult = 0, true
end
local function applied()
    local last
    for _, e in ipairs(handle.clientEvents) do
        if e.name == "kora_police:client:setArmour" then last = e.args[1] end
    end
    return last
end

h.test("armor, armour and heavyarmor are all registered usable", function()
    for _, name in ipairs({ "armor", "armour", "heavyarmor" }) do
        h.assertTrue(type(useables[name]) == "function", name .. " should have a usable handler")
    end
end)

h.test("the police armory vest is a registered armour item", function()
    local vest
    for _, item in ipairs(Config.armory.shops[1].items) do
        if item.name == "armor" then vest = item end
    end
    h.assertTrue(vest ~= nil and Config.armour.items[vest.name] ~= nil)
end)

h.test("using a vest runs the progress bar, removes one item and applies armour", function()
    reset()
    h.assertTrue(useables.armor(1, { name = "armor", slot = 4 }))
    h.assertEqual(progressCalls[1].name, "kora_police:armour:progress")
    h.assertEqual(progressCalls[1].payload.duration, Config.armour.progress.duration)
    h.assertEqual(#removed, 1); h.assertEqual(removed[1].name, "armor"); h.assertEqual(removed[1].slot, 4)
    h.assertEqual(applied(), 50)
end)

h.test("the armour alias behaves the same and heavyarmor gives 100", function()
    reset()
    h.assertTrue(useables.armour(1, { name = "armour", slot = 1 }))
    h.assertEqual(removed[1].name, "armour"); h.assertEqual(applied(), 50)
    reset()
    h.assertTrue(useables.heavyarmor(1, { name = "heavyarmor", slot = 2 }))
    h.assertEqual(applied(), 100)
end)

h.test("a cancelled progress bar keeps the item", function()
    reset(); progressResult = false
    h.assertEqual(useables.armor(1, { slot = 1 }), false)
    h.assertEqual(#removed, 0)
end)

h.test("already at or above the amount is refused and keeps the item", function()
    reset(); armour = 80
    h.assertEqual(useables.armor(1, { slot = 1 }), false)
    h.assertEqual(#removed, 0); h.assertEqual(#progressCalls, 0)
end)

h.test("add mode stacks but never exceeds 100", function()
    reset(); armour = 70
    Config.armour.items.armor.mode = "add"
    h.assertTrue(useables.armor(1, { slot = 1 }))
    h.assertEqual(applied(), 100)
    Config.armour.items.armor.mode = nil
end)

h.test("a client answering faster than the duration is ignored", function()
    reset()
    local real = Kora.callback.trigger
    Kora.callback.trigger = function() return true end
    h.assertEqual(useables.armor(1, { slot = 1 }), false)
    h.assertEqual(#removed, 0)
    Kora.callback.trigger = real
end)

h.report("armour")
