-- The local side of being cuffed: the replicated bag (not the animation) is the
-- state, the cuff animation/prop/controls are enforced while it holds, and
-- nothing runs once it is cleared.
local h = dofile('test/harness.lua')

local eventHandlers, commands, bagListeners, changeListeners = {}, {}, {}, {}
local threads = {}
local calls = { taskPlayAnim = 0, stopAnim = 0, props = 0, propsRemoved = 0, acquired = {}, released = 0, confirms = 0,
    clearSecondary = 0, clearTasks = 0, setEnabled = {}, phoneClosed = 0, holstered = 0, moved = {}, anims = {}, stopped = {},
    attached = {}, removedProps = {} }
local propFails, serverCuffed = false, true
local playingCuffAnim, ped, dead, ragdoll, vehicle = true, 100, false, false, false
-- Streaming the anim dict / the cuffs model takes frames in the game: when set,
-- the load yields once, like Kora.stream polling HasAnimDictLoaded/HasModelLoaded.
local slowAnimDict, slowPropModel = false, false
local handcuffsFlag = false
local timeouts = {}
local clock = 0
local resourceStates = { kora_target = 'started', kora_phone = 'started' }
local remotePeds = {}           -- serverId (== player index here) -> ped in scope on this client
local attachedEntity = {}       -- ped -> what it is attached to (escorted, the paired cuff)
local propRecords = {}          -- cuffs prop -> its calls.attached entry
local pedAttach = {}            -- every AttachEntityToEntity of a ped (the suspect onto the officer)
local seedList = nil            -- what kora_police:server:cuffedPlayers answers
local currentAction = nil       -- 'dict/clip' of the last non-idle clip played

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
function _G.GetPlayerPed(player) return remotePeds[player] or 0 end
function _G.GetPlayerFromServerId(serverId) if remotePeds[serverId] then return serverId end return -1 end
function _G.GetResourceState(name) return resourceStates[name] or 'missing' end
function _G.GetCurrentResourceName() return 'kora_police' end
function _G.GetGameTimer() return clock end
function _G.GetHashKey(name) return name end
function _G.SetCurrentPedWeapon(_, weapon) if weapon == 'WEAPON_UNARMED' then calls.holstered = calls.holstered + 1 end end
function _G.GetAnimDuration() return 4.5 end
function _G.IsEntityAttached(entity) return attachedEntity[entity] ~= nil end
-- Ped bone ids resolve through GetPedBoneIndex; bone names do not resolve on MP peds.
function _G.GetPedBoneIndex(_, boneId) return 1000 + boneId end
function _G.GetEntityBoneIndexByName() return -1 end
function _G.SetEntityCollision() end
function _G.AttachEntityToEntity(entity, target, boneIndex, ox, oy, oz, rx, ry, rz)
    local record = propRecords[entity]
    if record then
        record.entity, record.boneIndex = target, boneIndex
        record.offset, record.rotation = { x = ox, y = oy, z = oz }, { x = rx, y = ry, z = rz }
        return
    end
    attachedEntity[entity] = target
    pedAttach[#pedAttach + 1] = { entity = entity, target = target, boneIndex = boneIndex, x = ox, y = oy, z = oz, rz = rz }
end
function _G.DetachEntity(entity) if not propRecords[entity] then attachedEntity[entity] = nil end end
function _G.GetEntityHeading() return 90.0 end
function _G.GetEntityCoords() return { x = 0.0, y = 0.0, z = 0.0 } end
function _G.GetOffsetFromEntityInWorldCoords(_, x, y, z) return { x = x, y = y, z = z } end
function _G.SetEntityCoordsNoOffset(entity, x, y, z) calls.moved[#calls.moved + 1] = { entity = entity, x = x, y = y, z = z } end
function _G.SetEntityHeading(_, heading) calls.heading = heading end
function _G.NetworkGetPlayerIndexFromPed(entity) return entity end
function _G.DoesEntityExist(entity) return entity ~= nil and entity ~= 0 end
function _G.IsPedRagdoll() return ragdoll end
-- playingCuffAnim is the cuffed idle (mp_arresting idle); any other clip is currentAction.
function _G.IsEntityPlayingAnim(_, dict, clip)
    if clip == 'idle' then return playingCuffAnim end
    return currentAction == ('%s/%s'):format(dict, clip)
end
function _G.IsEntityAttachedToEntity(entity, target)
    if propRecords[entity] then return true end
    return attachedEntity[entity] == target
end
function _G.TaskPlayAnim(entity, dict, clip, _, _, duration, flag)
    calls.taskPlayAnim = calls.taskPlayAnim + 1
    calls.anims[#calls.anims + 1] = { entity = entity, dict = dict, clip = clip, duration = duration, flag = flag }
    playingCuffAnim = clip == 'idle'
    currentAction = clip ~= 'idle' and ('%s/%s'):format(dict, clip) or nil
end
function _G.StopAnimTask(_, dict, clip)
    calls.stopAnim = calls.stopAnim + 1
    calls.stopped[#calls.stopped + 1] = ('%s/%s'):format(dict, clip)
    if clip == 'idle' then playingCuffAnim = false end
    if currentAction == ('%s/%s'):format(dict, clip) then currentAction = nil end
end
function _G.ClearPedSecondaryTask() calls.clearSecondary = calls.clearSecondary + 1; playingCuffAnim = false end
function _G.ClearPedTasks() calls.clearTasks = calls.clearTasks + 1; currentAction = nil end
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
    entities = {
        create = function(model, coords)
            -- kora_lib asserts on a model it cannot load; the export call raises.
            if propFails then error(('Invalid model: %s'):format(model)) end
            if slowPropModel then Wait() end
            calls.props = calls.props + 1
            local prop = 900 + calls.props
            calls.attached[#calls.attached + 1] = { model = model, coords = coords, prop = prop }
            propRecords[prop] = calls.attached[#calls.attached]
            return prop
        end,
        remove = function(prop)
            calls.propsRemoved = calls.propsRemoved + 1
            calls.removedProps[prop] = true
            return true
        end,
    },
    state = { onChange = function(key, _, fn) bagListeners[key] = fn; return 1 end },
    callback = { trigger = function(name)
        if name == 'kora_police:server:cuffedPlayers' then return seedList end
        calls.confirms = calls.confirms + 1; return serverCuffed, false
    end },
    notify = { send = function() end },
}
local targetExports = {
    setEnabled = function(_, enabled) calls.setEnabled[#calls.setEnabled + 1] = enabled end,
    addGlobalType = function() return 1 end,
    removeGlobalType = function() return true end,
}
local phoneExports = { close = function() calls.phoneClosed = calls.phoneClosed + 1; return true end }
exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, resource)
        if resource == 'kora_target' then return targetExports end
        if resource == 'kora_phone' then return phoneExports end
        return setmetatable({}, { __index = function() return function() return 1 end end })
    end,
})

dofile('config.lua')
dofile('client/core.lua')
dofile('client/cuff_prop.lua')
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
    h.assertEqual(liveThreads(), 2, 'the cuff animation watch and the prop watch')
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
    h.assertEqual(liveThreads(), 2, 'still one animation watch and one prop watch')
end)

h.test('the soft flag follows the bag while cuffed', function()
    setOwnBag(true, true)
    h.assertTrue(Police.soft)
    setOwnBag(true, false)
    h.assertFalse(Police.soft)
end)

h.test('clearing the bag releases the controls, stops the animation and ends the watch', function()
    local prop = Police.cuffProps.get(5)
    h.assertTrue(prop ~= nil, 'the cuffs are on before the uncuff')
    setOwnBag(false, false)
    h.assertFalse(Police.cuffed)
    h.assertEqual(calls.released, 1)
    h.assertEqual(calls.stopAnim, 1)
    h.assertTrue(calls.removedProps[prop], 'the cuffs prop is deleted')
    h.assertEqual(Police.cuffProps.get(5), nil)
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
    h.assertEqual(liveThreads(), 2, 'the animation and prop watches still run')
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
    for index = props + 1, #calls.attached do
        h.assertTrue(calls.removedProps[calls.attached[index].prop], 'no prop is left on the freed player')
    end
    h.assertEqual(Police.cuffProps.get(5), nil)
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

-- t156: targeting off while cuffed, both sides of the paired cuff/uncuff
-- animations, and the handcuffs prop on every cuffed player in view.

local function cuffedEventBy(cuffed, actor)
    eventHandlers['qbpolice:client:cuffed'][1](cuffed, false, actor)
end

local function fireAll(name, ...)
    for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
end

local function contains(list, value)
    for _, entry in ipairs(list) do if entry == value then return true end end
    return false
end

local function setOtherBag(serverId, cuffed)
    bagListeners.koraCuffed({ bagName = ('player:%d'):format(serverId), key = 'koraCuffed', value = cuffed })
    bag(serverId).koraCuffed = cuffed
end

h.test('cuffed: the kora_target eye is switched off, and back on at the uncuff', function()
    freshUncuffed()
    calls.setEnabled = {}
    cuffedEvent(true); resume()
    h.assertEqual(#calls.setEnabled, 1)
    h.assertEqual(calls.setEnabled[1], false, 'setEnabled(false) while cuffed')
    cuffedEvent(true); resume()
    h.assertEqual(#calls.setEnabled, 1, 'a re-cuff does not switch it again')
    cuffedEvent(false)
    h.assertEqual(#calls.setEnabled, 2)
    h.assertEqual(calls.setEnabled[2], true, 'setEnabled(true) at the uncuff')
    cuffedEvent(false)
    h.assertEqual(#calls.setEnabled, 2, 'an uncuff of a free player leaves kora_target alone')

    setOwnBag(true, false); resume()
    h.assertEqual(calls.setEnabled[3], false, 'a cuff learned from the bag (join, reconnect) switches it off too')
    setOwnBag(false, false); resume(); resume()
    h.assertEqual(calls.setEnabled[4], true)
end)

h.test('Config.cuff.blockTargeting = false and a stopped kora_target leave targeting alone', function()
    freshUncuffed()
    calls.setEnabled = {}
    Config.cuff.blockTargeting = false
    cuffedEvent(true); resume(); cuffedEvent(false)
    h.assertEqual(#calls.setEnabled, 0)
    Config.cuff.blockTargeting = true
    resourceStates.kora_target = 'stopped'
    cuffedEvent(true); resume(); cuffedEvent(false)
    h.assertEqual(#calls.setEnabled, 0, 'no export call into a stopped resource')
    resourceStates.kora_target = 'started'
end)

h.test('a kora_target restart while cuffed switches the fresh eye off again; stopping kora_police switches it on', function()
    freshUncuffed()
    cuffedEvent(true); resume()
    calls.setEnabled = {}
    fireAll('onClientResourceStop', 'kora_target')
    fireAll('onClientResourceStart', 'kora_target')
    h.assertEqual(calls.setEnabled[1], false)
    local prop = Police.cuffProps.get(5)
    fireAll('onClientResourceStop', 'kora_police')
    h.assertEqual(calls.setEnabled[2], true, 'nobody would switch it back on once this resource is gone')
    h.assertTrue(calls.removedProps[prop], 'and the cuffs prop goes with the resource')
    freshUncuffed()
end)

h.test('a fresh cuff puts the weapon away and closes the phone once', function()
    freshUncuffed()
    local holstered, closed = calls.holstered, calls.phoneClosed
    cuffedEvent(true); resume()
    h.assertEqual(calls.holstered, holstered + 1)
    h.assertEqual(calls.phoneClosed, closed + 1)
    cuffedEvent(true); resume()
    h.assertEqual(calls.holstered, holstered + 1, 'not again on a re-cuff')
    h.assertEqual(calls.phoneClosed, closed + 1)
    freshUncuffed()
    Config.cuff.holsterWeapon, Config.cuff.closePhone = false, false
    cuffedEvent(true); resume()
    h.assertEqual(calls.holstered, holstered + 1)
    h.assertEqual(calls.phoneClosed, closed + 1)
    Config.cuff.holsterWeapon, Config.cuff.closePhone = true, true
    freshUncuffed()
    resourceStates.kora_phone = nil
    cuffedEvent(true); resume()
    h.assertEqual(calls.phoneClosed, closed + 1, 'no kora_phone, no call')
    resourceStates.kora_phone = 'started'
end)

h.test('a fresh cuff plays the suspect side of the paired clip attached in front of the officer, then the cuffed idle', function()
    freshUncuffed()
    remotePeds[1] = 501
    local before = #calls.anims
    cuffedEventBy(true, 1)
    local cfg = Config.cuff.anims.cuff.suspect
    local anim = calls.anims[before + 1]
    h.assertEqual(anim.dict, 'mp_arrest_paired')
    h.assertEqual(anim.clip, 'crook_p2_back_left')
    h.assertEqual(anim.duration, 3043, 'stopped at 3043 ms')
    h.assertEqual(anim.flag, 0)
    h.assertEqual(anim.entity, ped)
    local attach = pedAttach[#pedAttach]
    h.assertEqual(attach.entity, ped)
    h.assertEqual(attach.target, 501, 'attached to the officer\'s ped')
    h.assertEqual(attach.boneIndex, 0, 'on the officer\'s root (attach.bone = 0)')
    h.assertEqual(attach.x, cfg.attach.offset.x)
    h.assertEqual(attach.y, cfg.attach.offset.y, 'in front of the officer (+y in their frame)')
    h.assertEqual(attach.rz, cfg.attach.rotation.z)
    h.assertTrue(handcuffsFlag)
    h.assertEqual(#calls.anims, before + 1, 'the idle does not start over the paired clip')
    changeListeners.ped()
    h.assertEqual(#calls.anims, before + 1, 'and a restore while it plays leaves it alone')
    resume()
    h.assertEqual(#calls.anims, before + 2)
    h.assertEqual(calls.anims[before + 2].clip, 'idle', 'the cuffed idle takes over when it ends')
    h.assertTrue(playingCuffAnim)
end)

h.test('the paired clip is skipped in a vehicle and without an officer; no move for an escorted ped', function()
    freshUncuffed()
    vehicle = 4242
    local before = #calls.anims
    cuffedEventBy(true, 1); resume()
    h.assertEqual(calls.anims[before + 1].clip, 'idle', 'seated: straight to the cuffed idle')
    freshUncuffed()
    before = #calls.anims
    cuffedEvent(true); resume()
    h.assertEqual(calls.anims[before + 1].clip, 'idle', 'no officer named (a re-cuff, a join): no paired clip')
    freshUncuffed()
    attachedEntity[ped] = 777
    local moves = #pedAttach
    cuffedEventBy(true, 1)
    h.assertEqual(calls.anims[#calls.anims].clip, 'crook_p2_back_left')
    h.assertEqual(#pedAttach, moves, 'an attached (escorted) ped is not attached to the officer')
    attachedEntity[ped] = nil
    freshUncuffed()
    remotePeds[1] = nil
    moves = #pedAttach
    cuffedEventBy(true, 1)
    h.assertEqual(#pedAttach, moves, 'officer out of scope: played where the suspect stands')
    remotePeds[1] = 501
end)

h.test('an uncuff during the paired clip stops it and the idle never follows', function()
    freshUncuffed()
    cuffedEventBy(true, 1)
    h.assertEqual(currentAction, 'mp_arrest_paired/crook_p2_back_left')
    cuffedEvent(false)
    h.assertTrue(contains(calls.stopped, 'mp_arrest_paired/crook_p2_back_left'))
    local before = #calls.anims
    resume(); resume()
    h.assertEqual(#calls.anims, before, 'no cuffed idle on a freed player')
    h.assertFalse(handcuffsFlag)
    h.assertEqual(liveThreads(), 0)
end)

h.test('the officer plays their side of the cuff and uncuff animations from config', function()
    freshUncuffed()
    local fire = eventHandlers['kora_police:client:cuffAction'][1]
    local before = #calls.anims
    fire('cuff', 7)
    local anim = calls.anims[before + 1]
    h.assertEqual(anim.dict, 'mp_arrest_paired'); h.assertEqual(anim.clip, 'cop_p2_back_left')
    h.assertEqual(anim.duration, 3043); h.assertEqual(anim.flag, 0)
    fire('uncuff', 7)
    anim = calls.anims[before + 2]
    h.assertEqual(anim.dict, 'mp_arresting'); h.assertEqual(anim.clip, 'b_uncuff')
    h.assertEqual(anim.duration, -1, 'played once to its end')
    vehicle = 4242; fire('cuff', 7); vehicle = false
    h.assertEqual(#calls.anims, before + 2, 'not from a vehicle')
    fire('nonsense', 7)
    h.assertEqual(#calls.anims, before + 2)
    local officer = Config.cuff.anims.cuff.officer
    Config.cuff.anims.cuff.officer = nil
    fire('cuff', 7)
    h.assertEqual(#calls.anims, before + 2, 'a side removed from the config is skipped')
    Config.cuff.anims.cuff.officer = officer
end)

h.test('an uncuff by an officer plays the suspect side after the cuff is off; the re-check leaves it alone', function()
    freshUncuffed()
    cuffedEvent(true); resume()
    timeouts = {}
    local clears = calls.clearTasks
    cuffedEventBy(false, 1)
    local anim = calls.anims[#calls.anims]
    h.assertEqual(anim.dict, 'mp_arresting'); h.assertEqual(anim.clip, 'a_uncuff')
    h.assertEqual(calls.clearTasks, clears + 1, 'the cuff pose is cleared first')
    h.assertFalse(handcuffsFlag)
    local stops = calls.stopAnim
    runTimeouts()
    h.assertEqual(calls.stopAnim, stops, 'the one-off re-check does not stop the uncuff clip')
    h.assertEqual(currentAction, 'mp_arresting/a_uncuff')

    freshUncuffed()
    cuffedEvent(true); resume()
    local count = #calls.anims
    cuffedEvent(false)
    h.assertEqual(#calls.anims, count, 'an escape or a booking (no officer named) plays nothing')
end)

h.test('another player\'s cuffs: drawn from their bag on their ped, deleted when they are uncuffed', function()
    freshUncuffed()
    remotePeds[12] = 512
    local before = #calls.attached
    setOtherBag(12, true)
    local attached = calls.attached[before + 1]
    local cfg = Config.cuff.prop
    h.assertEqual(attached.entity, 512)
    h.assertEqual(attached.model, cfg.model)
    h.assertEqual(attached.boneIndex, 1000 + cfg.bone, 'the ped bone id, through GetPedBoneIndex')
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        h.assertEqual(attached.offset[axis], cfg.offset[axis])
        h.assertEqual(attached.rotation[axis], cfg.rotation[axis])
    end
    h.assertEqual(Police.cuffProps.get(12), attached.prop)
    h.assertFalse(Police.cuffed, 'their bag never cuffs this player')
    setOtherBag(12, false)
    h.assertTrue(calls.removedProps[attached.prop])
    h.assertEqual(Police.cuffProps.get(12), nil)
    resume()
    h.assertEqual(liveThreads(), 0, 'no cuffed player, no loop')
end)

h.test('cuffs follow a player in and out of view, onto a new ped, and off after a missed uncuff', function()
    freshUncuffed()
    remotePeds[13] = nil
    local before = #calls.attached
    setOtherBag(13, true)
    h.assertEqual(#calls.attached, before, 'out of scope: no prop')
    h.assertEqual(liveThreads(), 1, 'one prop watch while someone is cuffed')
    remotePeds[13] = 513
    resume()
    h.assertEqual(calls.attached[#calls.attached].entity, 513, 'attached once they come into view')
    local prop = Police.cuffProps.get(13)
    fireAll('onPlayerDropped', 13)
    remotePeds[13] = nil
    h.assertTrue(calls.removedProps[prop], 'deleted when they leave this client\'s scope')
    resume()
    h.assertEqual(Police.cuffProps.get(13), nil)
    remotePeds[13] = 514
    resume()
    prop = Police.cuffProps.get(13)
    h.assertEqual(calls.attached[#calls.attached].entity, 514, 'back when they return')
    remotePeds[13] = 515
    resume()
    h.assertTrue(calls.removedProps[prop], 'a respawned ped loses the old prop')
    h.assertEqual(calls.attached[#calls.attached].entity, 515, 'and gets a new one')
    prop = Police.cuffProps.get(13)
    bag(13).koraCuffed = false
    resume()
    h.assertTrue(calls.removedProps[prop], 'in view with a bag that says free: an uncuff this client missed')
    resume()
    h.assertEqual(liveThreads(), 0)
end)

h.test('a cuffed player who disconnects loses the cuffs on this client', function()
    freshUncuffed()
    remotePeds[14] = 514
    setOtherBag(14, true)
    local prop = Police.cuffProps.get(14)
    eventHandlers['kora_police:client:cuffedPlayerGone'][1](14)
    h.assertTrue(calls.removedProps[prop])
    resume()
    h.assertEqual(liveThreads(), 0)
    bag(14).koraCuffed = nil
end)

h.test('Config.cuff.prop.enabled = false draws no cuffs at all', function()
    freshUncuffed()
    Config.cuff.prop.enabled = false
    remotePeds[16] = 516
    local before = #calls.attached
    setOtherBag(16, true)
    cuffedEvent(true); resume()
    h.assertEqual(#calls.attached, before)
    Config.cuff.prop.enabled = true
    setOtherBag(16, false)
    freshUncuffed()
end)

h.test('players already cuffed when this client loads get their cuffs', function()
    remotePeds[20] = 520
    bag(20).koraCuffed = true
    seedList = { 20, 5 }
    dofile('client/cuff_prop.lua')
    h.assertEqual(calls.attached[#calls.attached].entity, 520)
    h.assertTrue(Police.cuffProps.get(20) ~= nil)
    h.assertEqual(Police.cuffProps.get(5), nil, 'its own cuffs follow its own cuff state, not the list')
end)

-- t162: kora_ambulance publishes emsDown = false for every living player, which
-- the client read as downed, so no cuff/uncuff clip ever played; and the cuffs
-- prop was attached by bone name, which MP peds do not resolve.

h.test('a living player (emsDown = false, as kora_ambulance publishes) still plays every cuff and uncuff clip', function()
    freshUncuffed()
    LocalPlayer.state.emsDown = false
    remotePeds[1] = 501
    local fire = eventHandlers['kora_police:client:cuffAction'][1]
    local before = #calls.anims
    fire('cuff', 7)
    h.assertEqual(calls.anims[before + 1] and calls.anims[before + 1].clip, 'cop_p2_back_left', 'officer side of the cuff')
    cuffedEventBy(true, 1)
    h.assertEqual(calls.anims[before + 2] and calls.anims[before + 2].clip, 'crook_p2_back_left', 'suspect side of the cuff')
    resume()
    h.assertEqual(calls.anims[#calls.anims].clip, 'idle', 'then the cuffed idle')
    playingCuffAnim = false
    resume()
    h.assertTrue(playingCuffAnim, 'the watch puts a lost cuffed idle back')
    cuffedEventBy(false, 1)
    h.assertEqual(calls.anims[#calls.anims].clip, 'a_uncuff', 'suspect side of the uncuff')
    fire('uncuff', 7)
    h.assertEqual(calls.anims[#calls.anims].clip, 'b_uncuff', 'officer side of the uncuff')
    LocalPlayer.state.emsDown = 'laststand'
    local count = #calls.anims
    fire('cuff', 7)
    h.assertEqual(#calls.anims, count, 'a downed officer plays nothing')
    LocalPlayer.state.emsDown = nil
    freshUncuffed()
end)

h.test('a living player (emsDown = false) is not restrained; last stand and dead are', function()
    bag(30).emsDown = false
    h.assertFalse(Police.isPedRestrained(30), 'free and alive: no rob or drag')
    bag(30).emsDown = 'alive'
    h.assertFalse(Police.isPedRestrained(30))
    bag(30).emsDown = 'laststand'
    h.assertTrue(Police.isPedRestrained(30))
    bag(30).emsDown = 'dead'
    h.assertTrue(Police.isPedRestrained(30))
end)

h.test('the 3043 ms cut is enforced: a one-off timer stops the clip if it is still on the ped', function()
    freshUncuffed()
    timeouts = {}
    local fire = eventHandlers['kora_police:client:cuffAction'][1]
    fire('cuff', 7)
    local cut
    for _, timeout in ipairs(timeouts) do if timeout.ms == 3043 then cut = timeout end end
    h.assertTrue(cut ~= nil, 'a timer at the configured duration')
    h.assertEqual(currentAction, 'mp_arrest_paired/cop_p2_back_left')
    cut.fn()
    h.assertEqual(currentAction, nil, 'stopped at 3043 ms')
    timeouts = {}
    fire('uncuff', 7)
    h.assertEqual(#timeouts, 0, 'a clip played to its end (-1) has no timer')
end)

h.test('cuff with the bag before the event: the cuffed idle is taken off so the paired clip shows', function()
    freshUncuffed()
    remotePeds[1] = 501
    setOwnBag(true, false)
    h.assertTrue(playingCuffAnim, 'the bag alone puts the cuffed idle on')
    calls.stopped = {}
    cuffedEventBy(true, 1)
    h.assertTrue(contains(calls.stopped, 'mp_arresting/idle'), 'the upper-body idle is stopped first')
    h.assertEqual(currentAction, 'mp_arrest_paired/crook_p2_back_left')
    freshUncuffed()
end)

h.test('the suspect is let go of the officer after attach.ms, unless an escort took over', function()
    freshUncuffed()
    remotePeds[1] = 501
    local ms = Config.cuff.anims.cuff.suspect.attach.ms
    local function runDetach()
        for _, timeout in ipairs(timeouts) do if timeout.ms == ms then timeout.fn() end end
    end
    timeouts = {}
    cuffedEventBy(true, 1)
    h.assertEqual(attachedEntity[ped], 501)
    runDetach()
    h.assertEqual(attachedEntity[ped], nil, 'detached after attach.ms')
    freshUncuffed()
    timeouts = {}
    cuffedEventBy(true, 1)
    Police.escortOfficer = 1
    runDetach()
    h.assertEqual(attachedEntity[ped], 501, 'an escort keeps the suspect attached')
    Police.escortOfficer, attachedEntity[ped] = nil, nil
    freshUncuffed()
end)

h.test('a cuffs bone given by name is turned into its ped bone id', function()
    freshUncuffed()
    remotePeds[17] = 517
    Config.cuff.prop.bone = 'PH_L_Hand'
    setOtherBag(17, true)
    h.assertEqual(calls.attached[#calls.attached].entity, 517)
    h.assertEqual(calls.attached[#calls.attached].boneIndex, 1000 + 60309)
    setOtherBag(17, false)
    Config.cuff.prop.bone = 60309
    resume()
end)

h.test('a cuffs prop that cannot be made is reported once in F8, not on every check', function()
    freshUncuffed()
    local printed, realPrint = {}, print
    print = function(message) printed[#printed + 1] = message end
    Config.cuff.prop.bone = 'NO_SUCH_BONE'
    remotePeds[18] = 518
    local before = #calls.attached
    setOtherBag(18, true)
    resume(); resume(); resume()
    print = realPrint
    Config.cuff.prop.bone = 60309
    h.assertEqual(#calls.attached, before, 'no prop without the bone')
    h.assertEqual(#printed, 1, 'one warning')
    h.assertTrue(tostring(printed[1]):find('NO_SUCH_BONE', 1, true) ~= nil)
    setOtherBag(18, false)
    resume()
end)

h.report('cuff_client')
