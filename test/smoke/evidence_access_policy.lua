-- Tests the actual policy function this build added to
-- qbinventory/config.lua's Config.qbinventory.containers.evidence.access --
-- the one qbinventory file this resource is allowed to touch. Loads that
-- real config.lua (not a copy) so a future edit to the policy is caught by
-- this test too.
local h = dofile('test/harness.lua')

_G.__TEST_JOBS = {}

_G.exports = setmetatable({}, {
    __index = function(_, resourceName)
        return setmetatable({}, {
            __index = function(_, fnName)
                return function(_, ...)
                    if resourceName == 'qbcore' and fnName == 'getJob' then
                        return _G.__TEST_JOBS[...]
                    end
                    return nil
                end
            end,
        })
    end,
})

local ok, err = pcall(dofile, '../qbinventory/config.lua')
h.assertTrue(ok, 'expected ../qbinventory/config.lua to load: ' .. tostring(err))

local access = Config.qbinventory.containers.evidence.access
h.assertTrue(type(access) == 'function', "evidence.access must be a function after this build's edit")

h.test('an on-duty police officer is granted access', function()
    __TEST_JOBS[1] = { name = 'police', onduty = true }
    local allowed = access(1, 'open', { evidenceId = 'case-1' })
    h.assertTrue(allowed)
end)

h.test('an off-duty police officer is denied', function()
    __TEST_JOBS[2] = { name = 'police', onduty = false }
    local allowed, reason = access(2, 'open', { evidenceId = 'case-1' })
    h.assertFalse(allowed)
    h.assertTrue(reason ~= nil)
end)

h.test('a non-police job is denied even on duty', function()
    __TEST_JOBS[3] = { name = 'ambulance', onduty = true }
    local allowed, reason = access(3, 'seize', { evidenceId = 'case-1' })
    h.assertFalse(allowed)
    h.assertTrue(reason ~= nil)
end)

h.test('a player with no job record at all is denied', function()
    local allowed, reason = access(999, 'release', { evidenceId = 'case-1' })
    h.assertFalse(allowed)
    h.assertTrue(reason ~= nil)
end)

h.test('the same on-duty officer is granted for every action name (open/seize/release)', function()
    __TEST_JOBS[1] = { name = 'police', onduty = true }
    h.assertTrue(access(1, 'open', {}))
    h.assertTrue(access(1, 'seize', {}))
    h.assertTrue(access(1, 'release', {}))
end)

h.report('evidence_access_policy')
