-- The local side of being cuffed: the replicated bag (not the animation) is the
-- state, the cuff animation/prop/controls are enforced while it holds, and
-- nothing runs once it is cleared.
local h = dofile('test/harness.lua')

local eventHandlers, commands, bagListeners, changeListeners = {}, {}, {}, {}
local threads = {}
local calls = { taskPlayAnim = 0, stopAnim = 0, props = 0, propsRemoved = 0, acquired = {}, released = 0, confirms = 0 }
local propFails, serverCuffed = false, true
local playingCuffAnim, ped, dead, ragdoll = true, 100, false, false

function _G.RegisterNetEvent(name, cb) if cb then eventHandlers[name] = { cb } end end
function _G.AddEventHandler(name, cb) eventHandlers[name] = eventHandlers[name] or {}; table.insert(eventHandlers[name], cb) end
function _G.TriggerEvent(name, ...) for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end end
function _G.RegisterCommand(name, fn) commands[name] = fn end
function _G.TriggerServerEvent() end
function _G.exports(_, _) end
function _G.CreateThread(fn) local co = coroutine.create(fn); threads[#threads + 1] = co; assert(coroutine.resume(co)) end
function _G.Wait() coroutine.yield() end
function _G.GetPlayerServerId(index) if index == 0 then return 5 end return index end
function _G.PlayerId() return 0 end
function _G.GetActivePlayers() return {} end
function _G.GetPlayerPed() return 0 end
function _G.NetworkGetPlayerIndexFromPed(entity) return entity end
function _G.DoesEntityExist(entity) return entity ~= nil and entity ~= 0 end
function _G.IsPedRagdoll() return ragdoll end
function _G.IsEntityPlayingAnim() return playingCuffAnim end
function _G.IsEntityAttachedToEntity() return true end
function _G.TaskPlayAnim() calls.taskPlayAnim = calls.taskPlayAnim + 1; playingCuffAnim = true end
function _G.StopAnimTask() calls.stopAnim = calls.stopAnim + 1 end
function _G.RemoveAnimDict() end
function _G.SetEnableHandcuffs() end
function _G.vector3(x, y, z) return { x = x, y = y, z = z } end
function _G.vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end
LocalPlayer = { state = {} }

local function resume()
    for index = #threads, 1, -1 do
        if coroutine.status(threads[index]) == 'dead' then table.remove(threads, index)
        else assert(coroutine.resume(threads[index])) end
    end
end

local function liveThreads()
    local count = 0
    for _, co in ipairs(threads) do if coroutine.status(co) ~= 'dead' then count = count + 1 end end
    return count
end

local bags = {}
local function bag(serverId) bags[serverId] = bags[serverId] or {}; return bags[serverId] end
function _G.Player(serverId) return { state = bag(serverId) } end

Kora = {
    compat = dofile('../kora_lib/compat/provider.lua')(),
    cache = {
        ped = function() return ped end, playerId = function() return 0 end, isDead = function() return dead end,
        coords = function() return vector3(0, 0, 0) end,
        onChange = function(key, fn) changeListeners[key] = fn end,
    },
    stream = { loadAnimDict = function(dict) return dict end },
    controls = {
        acquire = function(ids, options) calls.acquired[#calls.acquired + 1] = { ids = ids, options = options }; return #calls.acquired end,
        release = function() calls.released = calls.released + 1; return true end,
    },
    anim = {
        attachProp = function(entity)
            -- kora_lib asserts on a ped that does not exist; the export call raises.
            if propFails then error(('Invalid entity: %s'):format(entity)) end
            calls.props = calls.props + 1; return 900 + calls.props
        end,
        detachProp = function() calls.propsRemoved = calls.propsRemoved + 1; return true end,
    },
    state = { onChange = function(key, _, fn) bagListeners[key] = fn; return 1 end },
    callback = { trigger = function() calls.confirms = calls.confirms + 1; return serverCuffed, false end },
    notify = { send = function() end },
}
exports = setmetatable({}, {
    __call = function() end,
    __index = function() return setmetatable({}, { __index = function() return function() return 1 end end }) end,
})

dofile('config.lua')
dofile('client/core.lua')
dofile('client/cuff.lua')

local function setOwnBag(cuffed, soft)
    LocalPlayer.state.koraCuffedSoft = soft
    LocalPlayer.state.koraCuffed = cuffed
    bagListeners.koraCuffed({ bagName = 'player:5', key = 'koraCuffed', value = cuffed })
end

h.test('nothing runs or is applied while the bag says free', function()
    h.assertFalse(Police.cuffed)
    h.assertEqual(calls.taskPlayAnim, 0)
    h.assertEqual(liveThreads(), 0)
    h.assertEqual(calls.confirms, 0, 'joining uncuffed asks the server nothing')
end)

h.test('the bag cuffs the local player: animation, prop, control lease and watch', function()
    setOwnBag(true, false)
    h.assertTrue(Police.cuffed)
    h.assertEqual(calls.taskPlayAnim, 1)
    h.assertEqual(calls.props, 1)
    h.assertEqual(#calls.acquired, 1)
    h.assertEqual(calls.acquired[1].ids, Config.cuff.disabledControls)
    h.assertTrue(calls.acquired[1].options.disablePlayerFiring)
    h.assertEqual(liveThreads(), 1)
    h.assertEqual(calls.confirms, 1, 'a cuff learned from the bag is confirmed with the server once')
end)

h.test('a change of someone else\'s bag is ignored', function()
    bagListeners.koraCuffed({ bagName = 'player:9', key = 'koraCuffed', value = false })
    h.assertTrue(Police.cuffed)
end)

h.test('the cuff animation is put back when an emote replaced it, and not before', function()
    resume()
    h.assertEqual(calls.taskPlayAnim, 1, 'animation still playing: nothing to do')
    playingCuffAnim = false
    resume()
    h.assertEqual(calls.taskPlayAnim, 2)
    h.assertTrue(playingCuffAnim)
    h.assertEqual(calls.props, 1, 'the prop is kept, not attached again')
end)

h.test('a dead/downed or ragdolling player keeps their own animation', function()
    playingCuffAnim = false; dead = true; resume()
    h.assertEqual(calls.taskPlayAnim, 2)
    dead = false; LocalPlayer.state.emsDown = 'laststand'; resume()
    h.assertEqual(calls.taskPlayAnim, 2)
    LocalPlayer.state.emsDown = nil; ragdoll = true; resume()
    h.assertEqual(calls.taskPlayAnim, 2)
    ragdoll = false; resume()
    h.assertEqual(calls.taskPlayAnim, 3)
end)

h.test('a new ped (respawn) gets the animation straight away', function()
    playingCuffAnim = false; ped = 101
    changeListeners.ped()
    h.assertEqual(calls.taskPlayAnim, 4)
end)

h.test('a re-cuff event re-applies the animation without a second control lease', function()
    eventHandlers['qbpolice:client:cuffed'][1](true, false)
    h.assertEqual(calls.taskPlayAnim, 5)
    h.assertEqual(#calls.acquired, 1)
    h.assertEqual(liveThreads(), 1, 'still one watch thread')
end)

h.test('the soft flag follows the bag while cuffed', function()
    setOwnBag(true, true)
    h.assertTrue(Police.soft)
    setOwnBag(true, false)
    h.assertFalse(Police.soft)
end)

h.test('clearing the bag releases the controls, stops the animation and ends the watch', function()
    setOwnBag(false, false)
    h.assertFalse(Police.cuffed)
    h.assertEqual(calls.released, 1)
    h.assertEqual(calls.stopAnim, 1)
    h.assertEqual(calls.propsRemoved, 1)
    resume(); resume()
    h.assertEqual(liveThreads(), 0, 'the watch thread is gone once free')
    playingCuffAnim = false
    local before = calls.taskPlayAnim
    resume()
    h.assertEqual(calls.taskPlayAnim, before)
end)

h.test('target menus read the replicated bag of the player they aim at', function()
    bag(7).koraCuffed = true
    h.assertTrue(Police.isPedCuffed(7))
    bag(8).koraCuffed = false
    h.assertFalse(Police.isPedCuffed(8))
    h.assertFalse(Police.isPedRestrained(8))
    bag(8).emsDown = 'laststand'
    h.assertTrue(Police.isPedRestrained(8))
    Config.incapacitated.downed = false
    h.assertFalse(Police.isPedRestrained(8))
    Config.incapacitated.downed = true
    bag(7).emsDown = nil
    Config.incapacitated.cuffed = false
    h.assertFalse(Police.isPedRestrained(7))
    Config.incapacitated.cuffed = true
end)

h.test('/uncuff is registered from Config.cuff.uncuffCommand', function()
    h.assertTrue(commands[Config.cuff.uncuffCommand] ~= nil)
end)

h.test('a failing prop attach raises nothing and keeps the cuff state consistent', function()
    setOwnBag(false, false); resume(); resume()
    local confirmsBefore, releasedBefore = calls.confirms, calls.released
    propFails, serverCuffed = true, true
    setOwnBag(true, false)
    resume()
    h.assertTrue(Police.cuffed)
    h.assertTrue(playingCuffAnim, 'the animation is still applied')
    h.assertEqual(liveThreads(), 1, 'the watch still runs')
    h.assertEqual(calls.confirms, confirmsBefore + 1, 'the server is asked once')
    resume(); resume()
    h.assertEqual(calls.confirms, confirmsBefore + 1, 'and not again on every watch tick')
    h.assertEqual(calls.released, releasedBefore)
    propFails = false
end)

h.test('a cuff the server does not confirm frees the client', function()
    setOwnBag(false, false); resume(); resume()
    local releasedBefore = calls.released
    propFails, serverCuffed = true, false
    setOwnBag(true, false)
    resume()
    h.assertFalse(Police.cuffed, 'freed by the server answer')
    h.assertEqual(calls.released, releasedBefore + 1, 'the control lease is released')
    propFails, serverCuffed = false, true
    LocalPlayer.state.koraCuffed = false
end)

h.test('cuffed while joining with no ped yet: no error, visuals once the ped exists', function()
    setOwnBag(false, false); resume(); resume()
    ped, playingCuffAnim = 0, false
    local animsBefore = calls.taskPlayAnim
    setOwnBag(true, false)
    resume()
    h.assertTrue(Police.cuffed)
    h.assertEqual(calls.taskPlayAnim, animsBefore, 'nothing played on a missing ped')
    ped = 102
    changeListeners.ped()
    h.assertEqual(calls.taskPlayAnim, animsBefore + 1)
    setOwnBag(false, false)
    h.assertFalse(Police.cuffed)
end)

h.report('cuff_client')
