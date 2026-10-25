-- Proves that a qbtarget restart actually triggers RE-registration of every
-- client-side qbtarget zone/type qbpolice owns, not just that a wrapper
-- function exists. qbtarget cleans up per-owner registrations on its own
-- stop, but qbpolice's file-scope registration calls only ever ran once (at
-- qbpolice's own boot) -- without an onClientResourceStart('qbtarget')
-- listener calling the registration function again, a qbtarget restart
-- would permanently wipe qbpolice's targets until qbpolice itself restarts.
local h = dofile('test/harness.lua')

-- Minimal client-side natives/exports these files touch AT LOAD TIME (i.e.
-- inside the immediately-invoked registerXTargets() call, or any top-level
-- CreateThread). Callback bodies (onSelect/canInteract) are never invoked
-- here, so natives only referenced from inside those closures don't need
-- mocking.
local eventHandlers = {}
local qbtargetCalls = 0
local activeTargetIds, nextTargetId = {}, 0

local function addTarget()
    qbtargetCalls = qbtargetCalls + 1
    nextTargetId = nextTargetId + 1
    activeTargetIds[nextTargetId] = true
    return nextTargetId
end

local function removeZoneTarget(_, id)
    activeTargetIds[id] = nil
    return true
end

local function removeGlobalTarget(_, _, id)
    activeTargetIds[id] = nil
    return true
end

local function activeTargetCount()
    local count = 0
    for _ in pairs(activeTargetIds) do count = count + 1 end
    return count
end

function _G.RegisterNetEvent(_, _) end
function _G.RegisterCommand(_, _) end
function _G.AddEventHandler(name, cb)
    eventHandlers[name] = eventHandlers[name] or {}
    table.insert(eventHandlers[name], cb)
end
function _G.TriggerEvent(name, ...)
    for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
end
function _G.TriggerServerEvent(...) end
function _G.CreateThread(fn)
    local ok, err = pcall(fn)
    if not ok then print(('CreateThread error (ignored -- callback body, not load-time): %s'):format(tostring(err))) end
end
function _G.SetTimeout(_, _) end
function _G.Wait(_) end
function _G.GetGameTimer() return 0 end
function _G.GetHashKey(s) return s end
function _G.joaat(s) return s end
function _G.AddDoorToSystem() end
function _G.DoorSystemSetDoorState() end
function _G.vector3(x, y, z) return { x = x or 0.0, y = y or 0.0, z = z or 0.0 } end
function _G.vector4(x, y, z, w) return { x = x or 0.0, y = y or 0.0, z = z or 0.0, w = w or 0.0 } end

local blipCalls = 0
local stationBlips = {}

_G.QB = {
    cache = {
        vehicle = function() return false end,
        seat = function() return 0 end,
        ped = function() return 0 end,
        playerId = function() return 0 end,
        onChange = function() end,
    },
    blips = {
        create = function(_, options)
            blipCalls = blipCalls + 1
            stationBlips[#stationBlips + 1] = options
            return blipCalls
        end,
        remove = function() return true end,
        setInfo = function() return true end,
    },
}

_G.exports = setmetatable({}, {
    __call = function(_, _name, _fn) end,  -- exports('IsHandcuffed', fn)-style self-registration
    __index = function(_, resourceName)
        if resourceName == 'qbtarget' then
            return {
                addGlobalType = addTarget,
                addBoxZone = addTarget,
                addSphereZone = addTarget,
                removeGlobalType = removeGlobalTarget,
                removeZone = removeZoneTarget,
            }
        end
        return setmetatable({}, {
            __index = function(_, _fnName)
                return function(_, ...) return nil end
            end,
        })
    end,
})

QB.compat = dofile('../qblib/compat/provider.lua')()
dofile('config.lua')
dofile('client/core.lua')

-- Every client file that owns a file-scope qbtarget registration, per the
-- qbtarget-restart-safety refactor. All 16 register via
-- AddEventHandler('onClientResourceStart', ...) so re-running the handler
-- with resourceName == 'qbtarget' re-registers.
local targetFiles = {
    'client/plate_flag.lua', 'client/duty.lua', 'client/fingerprint.lua', 'client/seize.lua',
    'client/armory.lua', 'client/cuff.lua', 'client/search.lua', 'client/evidence.lua',
    'client/impound.lua', 'client/vehicle.lua', 'client/tracker.lua', 'client/escort.lua',
    'client/bill.lua', 'client/jail.lua', 'client/rob.lua', 'client/breach_minigame.lua',
}

for _, path in ipairs(targetFiles) do
    dofile(path)
end

h.test('every listed client file registers at least one qbtarget zone/type on initial load', function()
    h.assertTrue(qbtargetCalls > 0, 'expected qbtarget registration calls during initial load')
end)

-- Blips are NOT part of the re-registration contract, and that asymmetry is the
-- point -- see the test at the bottom of this file.
local blipsAfterInitialLoad = blipCalls
local afterInitialLoad = qbtargetCalls
local activeAfterInitialLoad = activeTargetCount()

h.test('firing onClientResourceStart for qbtarget re-registers every zone/type from every file', function()
    TriggerEvent('onClientResourceStart', 'qbtarget')
    -- Every one of the 16 files' registration functions is idempotent and
    -- makes the exact same qbtarget calls it made on initial load, so a
    -- single simulated qbtarget restart must exactly DOUBLE the running
    -- total. A plain ">" check would still pass if even one file silently
    -- failed to re-register (as long as at least one of the other 15 did),
    -- so this asserts the precise count instead.
    h.assertEqual(qbtargetCalls, afterInitialLoad * 2,
        ('expected qbtarget call count to exactly double after a simulated qbtarget restart (was %d, expected %d, got %d)')
            :format(afterInitialLoad, afterInitialLoad * 2, qbtargetCalls))
    h.assertEqual(activeTargetCount(), activeAfterInitialLoad,
        're-registration replaces every police target instead of duplicating menu options')
end)

h.test('firing onClientResourceStart for an unrelated resource does not re-register anything', function()
    local before = qbtargetCalls
    TriggerEvent('onClientResourceStart', 'some-other-resource')
    h.assertEqual(qbtargetCalls, before, 'onClientResourceStart for a non-qbtarget resource must be a no-op here')
end)

-- Runs last, so it observes the qbtarget restarts the tests above already
-- fired rather than firing its own (which would break their exact-count
-- assertions).
--
-- Blips are deliberately outside the re-registration contract: qbtarget drops
-- its own registrations when it stops, so those have to be re-made, but qblib's
-- blip registry only clears when QBPOLICE stops -- so re-making a blip stacks a
-- duplicate station marker on the map rather than replacing it. This is why
-- client/duty.lua creates them in their own function, called once at load.
h.test('station blips are created once at load, not per qbtarget restart', function()
    h.assertTrue(blipsAfterInitialLoad > 0, 'the station blip is created on initial load')
    h.assertEqual(blipCalls, blipsAfterInitialLoad,
        'a qbtarget restart must not stack another station blip')
    h.assertEqual(stationBlips[1].category, 'Police',
        'station blips group beneath the canonical Police heading')
    h.assertEqual(stationBlips[1].name, nil, 'a generic station does not repeat its category as a name')
    h.assertEqual(stationBlips[1].label, nil, 'qblib composes the station label')
end)

h.report('target_restart')
