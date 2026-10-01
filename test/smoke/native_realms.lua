local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install()
dofile('config.lua')
dofile('server/core.lua')
handle.addPlayer(1, { job = { name = 'police', onduty = true, grade = { level = 1 } } })
handle.addPlayer(2, { metadata = { ishandcuffed = true } })
handle.addPlayer(3)
local hashes = { WEAPON_PISTOL = 100, WEAPON_BAT = 200, COMPONENT_AT_PI_SUPP = 300,
    COMPONENT_AT_PI_SUPP_02 = 301, COMPONENT_AT_AR_SUPP = 302,
    COMPONENT_AT_AR_SUPP_02 = 303, COMPONENT_AT_SR_SUPP = 304 }
joaat = function(value) return hashes[value:upper()] or 999 end
local selected, equipped = 100, nil
GetSelectedPedWeapon = function() return selected end
handle.exportImpls.qbinventory.GetEquippedWeapon = function() return equipped end
HasPedGotWeaponComponent, NetworkDoesNetworkIdExist, PlaceObjectOnGroundProperly = nil, nil, nil
dofile('server/callbacks.lua')
dofile('server/escort.lua')
dofile('server/spikes.lua')

h.test('suppressor detection uses the selected inventory weapon and trusted mapped components', function()
    local callback = QB.callback.registry['police:IsSilencedWeapon']
    h.assertFalse(callback(2))
    equipped = { slot = 1, name = 'weapon_pistol', components = { 'COMPONENT_AT_PI_SUPP' } }
    h.assertTrue(callback(2))
    h.assertTrue(callback(1, 2))
    h.assertFalse(callback(3, 2), 'other players require police permission')
    selected = 200
    h.assertFalse(callback(2), 'an inventory component cannot silence a different selected weapon')
    selected = 100
    equipped.components = { 300 }
    h.assertTrue(callback(2), 'hash mappings are accepted too')
    equipped.components = { 'ordinary_component' }
    h.assertFalse(callback(2))
end)

h.test('spikes and suspect seating work without client-only server natives', function()
    local id = Police.deploySpike(1, { x = 2, y = 0, z = 0 })
    h.assertTrue(type(id) == 'number')
    h.assertTrue(Police.spikes[id] ~= nil)
    NetworkGetEntityFromNetworkId = function(netId) return netId == id and id - 1000 or 0 end
    h.assertFalse(Police.putInVehicle(1, 2, 'invalid'))
    h.assertFalse(Police.putInVehicle(1, 2, 9999))
    h.assertTrue(Police.putInVehicle(1, 2, id, 0))
    local event = handle.lastClient('qbpolice:client:putInVehicle')
    h.assertEqual(event.target, 2)
    h.assertEqual(event.args[1], id)
    h.assertEqual(event.args[2], 0)
    h.assertTrue(Police.removeSpike(id))
    h.assertEqual(Police.spikesByOfficer[1], 0)
end)
h.report('native realms')
