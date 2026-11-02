-- The local side of being cuffed: the replicated bag (not the animation) is the
-- state, the cuff animation/prop/controls are enforced while it holds, and
-- nothing runs once it is cleared.
local h = dofile('test/harness.lua')

local eventHandlers, commands, bagListeners, changeListeners = {}, {}, {}, {}
local threads = {}
local calls = { taskPlayAnim = 0, stopAnim = 0, props = 0, propsRemoved = 0, acquired = {}, released = 0, confirms = 0,
    clearSecondary = 0, clearTasks = 0 }
local propFails, serverCuffed = false, true
local playingCuffAnim, ped, dead, ragdoll, vehicle = true, 100, false, false, false
-- Streaming the anim dict / the cuffs model takes frames in the game: when set,
-- the load yields once, like Kora.stream polling HasAnimDictLoaded/HasModelLoaded.
local slowAnimDict, slowPropModel = false, false
local handcuffsFlag = false
local timeouts = {}

function _G.RegisterNetEvent(name, cb) if cb then eventHandlers[name] = { cb } end end
function _G.AddEventHandler(name, cb) eventHandlers[name] = eventHandlers[name] or {}; table.insert(eventHandlers[name], cb) end
function _G.CreateThread(fn) local co = coroutine.create(fn); threads[#threads + 1] = co; assert(coroutine.resume(co)) end
-- Like the FiveM runtime, every event handler runs in its own coroutine: one that
-- yields (streaming an asset) lets TriggerEvent return and is resumed later.
function _G.TriggerEvent(name, ...)
    local args = table.pack(...)
    for _, fn in ipairs(eventHandlers[name] or {}) do
        CreateThread(function() fn(table.unpack(args, 1, args.n)) end)
    end
end
function _G.RegisterCommand(name, fn) commands[name] = fn end
function _G.TriggerServerEvent() end
function _G.exports(_, _) end
function _G.Wait() coroutine.yield() end
function _G.SetTimeout(ms, fn) timeouts[#timeouts + 1] = { ms = ms, fn = fn } end
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
function _G.StopAnimTask() calls.stopAnim = calls.stopAnim + 1; playingCuffAnim = false end
function _G.ClearPedSecondaryTask() calls.clearSecondary = calls.clearSecondary + 1; playingCuffAnim = false end
function _G.ClearPedTasks() calls.clearTasks = calls.clearTasks + 1 end
function _G.RemoveAnimDict() end
function _G.SetEnableHandcuffs(_, enabled) handcuffsFlag = enabled end
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
        vehicle = function() return vehicle end,
        coords = function() return vector3(0, 0, 0) end,
        onChange = function(key, fn) changeListeners[key] = fn end,
    },
    stream = { loadAnimDict = function(dict) if slowAnimDict then Wait() end return dict end },
    controls = {
        acquire = function(ids, options) calls.acquired[#calls.acquired + 1] = { ids = ids, options = options }; return #calls.acquired end,
        release = function() calls.released = calls.released + 1; return true end,
    },
    anim = {
        attachProp = function(entity)
            -- kora_lib asserts on a ped that does not exist; the export call raises.
            if propFails then error(('Invalid entity: %s'):format(entity)) end
            if slowPropModel then Wait() end
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
dofile(arg[1] or 'client/cuff.lua')

-- FiveM runs a state bag change handler BEFORE the bag stores the new value:
-- inside the handler the bag still reads the old one.
local function setBagKey(key, value)
    bagListeners[key]({ bagName = 'player:5', key = key, value = value })
    LocalPlayer.state[key] = value
end

-- The order server/cuff.lua publishes in: the soft flag, then the cuff.
local function setOwnBag(cuffed, soft)
    setBagKey('koraCuffedSoft', cuffed and soft or false)
    setBagKey('koraCuffed', cuffed)
end

local function cuffedEvent(cuffed, soft)
    eventHandlers['qbpolice:client:cuffed'][1](cuffed, soft or false)
end

local function runTimeouts()
    local pending = timeouts
    timeouts = {}
    for _, timeout in ipairs(pending) do timeout.fn() end
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
    cuffedEvent(true, false)
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

local function freshUncuffed()
    setOwnBag(false, false); cuffedEvent(false); resume(); resume(); runTimeouts()
    slowAnimDict, slowPropModel, propFails, serverCuffed, vehicle = false, false, false, true, false
    Config.cuff.clearTasksOnUncuff, Config.cuff.uncuffRecheckMs = true, 1000
end

local function leasesHeld() return #calls.acquired - calls.released end

h.test('/uncuff (event first, bag after): the bag still reading cuffed never puts the cuff back', function()
    freshUncuffed()
    cuffedEvent(true); setOwnBag(true, false); resume()
    h.assertTrue(Police.cuffed)
    local anims = calls.taskPlayAnim
    cuffedEvent(false)
    -- the bag handlers run while LocalPlayer.state.koraCuffed still says true
    setOwnBag(false, false)
    resume(); resume()
    h.assertFalse(Police.cuffed, 'still uncuffed after the bag update')
    h.assertEqual(calls.taskPlayAnim, anims, 'the cuff animation is not played again')
    h.assertEqual(leasesHeld(), 0, 'no control lease is left')
    h.assertFalse(handcuffsFlag, 'the handcuffed ped flag is off')
    h.assertFalse(playingCuffAnim, 'the cuff animation is stopped')
    h.assertEqual(liveThreads(), 0, 'the watch thread is gone')
end)

h.test('uncuff with the bag first, then the event: fully free', function()
    freshUncuffed()
    setOwnBag(true, true); cuffedEvent(true, true); resume()
    h.assertTrue(Police.cuffed and Police.soft)
    setOwnBag(false, false)
    h.assertFalse(Police.cuffed, 'the bag alone frees the player')
    cuffedEvent(false)
    resume(); resume()
    h.assertFalse(Police.cuffed)
    h.assertEqual(leasesHeld(), 0)
    h.assertFalse(handcuffsFlag)
    h.assertFalse(playingCuffAnim)
end)

h.test('a cuff from the bag then the event holds one lease and stays cuffed', function()
    freshUncuffed()
    setOwnBag(true, false)
    cuffedEvent(true)
    resume()
    h.assertTrue(Police.cuffed)
    h.assertEqual(leasesHeld(), 1)
    h.assertTrue(handcuffsFlag)
end)

h.test('an uncuff that lands while the cuff animation is still streaming leaves nothing on the ped', function()
    freshUncuffed()
    local anims, props = calls.taskPlayAnim, calls.props
    slowAnimDict = true
    cuffedEvent(true)
    h.assertTrue(Police.cuffed)
    cuffedEvent(false)
    slowAnimDict = false
    resume(); resume(); resume()
    h.assertFalse(Police.cuffed)
    h.assertEqual(calls.taskPlayAnim, anims, 'the loaded animation is not played on a freed player')
    h.assertEqual(calls.props, props, 'no prop is attached')
    h.assertFalse(handcuffsFlag)
    h.assertEqual(leasesHeld(), 0)
    h.assertEqual(liveThreads(), 0)
end)

h.test('an uncuff that lands while the cuffs prop is streaming deletes the late prop', function()
    freshUncuffed()
    local removed = calls.propsRemoved
    slowPropModel = true
    cuffedEvent(true)
    cuffedEvent(false)
    slowPropModel = false
    resume(); resume(); resume()
    h.assertFalse(Police.cuffed)
    h.assertEqual(calls.propsRemoved, removed + 1, 'the prop created after the uncuff is removed at once')
    h.assertFalse(handcuffsFlag)
    h.assertFalse(playingCuffAnim)
    h.assertEqual(leasesHeld(), 0)
end)

h.test('uncuff clears the ped tasks on foot, not in a vehicle, and not when turned off', function()
    freshUncuffed()
    cuffedEvent(true); resume()
    local secondary, tasks = calls.clearSecondary, calls.clearTasks
    cuffedEvent(false)
    h.assertEqual(calls.clearSecondary, secondary + 1, 'the secondary (upper-body) cuff task is cleared')
    h.assertEqual(calls.clearTasks, tasks + 1)

    cuffedEvent(true); resume()
    vehicle = 4242
    tasks = calls.clearTasks
    cuffedEvent(false)
    h.assertEqual(calls.clearTasks, tasks, 'a seated player keeps their seat task')
    vehicle = false

    Config.cuff.clearTasksOnUncuff = false
    cuffedEvent(true); resume()
    tasks = calls.clearTasks
    local stops = calls.stopAnim
    cuffedEvent(false)
    h.assertEqual(calls.clearTasks, tasks)
    h.assertEqual(calls.stopAnim, stops + 1, 'the cuff animation itself still stops')
    Config.cuff.clearTasksOnUncuff = true
end)

h.test('a client that was never cuffed keeps what it is doing when told it is free', function()
    freshUncuffed()
    playingCuffAnim = false
    local secondary, tasks = calls.clearSecondary, calls.clearTasks
    cuffedEvent(false)
    h.assertEqual(calls.clearSecondary, secondary)
    h.assertEqual(calls.clearTasks, tasks)
end)

h.test('one deferred re-check after an uncuff takes a cuff animation that came back off again', function()
    freshUncuffed()
    cuffedEvent(true); resume()
    timeouts = {}
    cuffedEvent(false)
    h.assertEqual(#timeouts, 1, 'a single one-shot timer, no loop')
    h.assertEqual(timeouts[1].ms, Config.cuff.uncuffRecheckMs)
    playingCuffAnim = true
    local stops = calls.stopAnim
    runTimeouts()
    h.assertEqual(calls.stopAnim, stops + 1)
    h.assertFalse(playingCuffAnim)
    h.assertEqual(#timeouts, 0, 'it does not reschedule itself')

    Config.cuff.uncuffRecheckMs = 0
    cuffedEvent(true); resume()
    cuffedEvent(false)
    h.assertEqual(#timeouts, 0, 'uncuffRecheckMs = 0 turns it off')
    Config.cuff.uncuffRecheckMs = 1000
end)

h.test('a re-check is skipped when the player is cuffed again before it runs', function()
    freshUncuffed()
    cuffedEvent(true); resume()
    timeouts = {}
    cuffedEvent(false)
    cuffedEvent(true); resume()
    local stops = calls.stopAnim
    runTimeouts()
    h.assertEqual(calls.stopAnim, stops)
    h.assertTrue(Police.cuffed)
    h.assertTrue(handcuffsFlag)
end)

h.report('cuff_client')
