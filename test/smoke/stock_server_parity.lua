-- qb-policejob parity, second pass: stash/trash/evidence, road props, heli
-- spotlight, tracker toggle, evidence events, impound payloads, RobPlayer.
local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install()
dofile('config.lua')
_G.joaat = function(v) return 999 end
_G.GetEntityHeading = function() return 0.0 end
_G.SetEntityHeading = function() end
_G.FreezeEntityPosition = function() end
_G.GetVehicleBodyHealth = function() return 900.0 end
_G.GetVehicleEngineHealth = function() return 800.0 end
local vehicleOf, vehicleType, seatOf = {}, {}, {}
_G.GetVehiclePedIsIn = function(ped) return vehicleOf[ped] or 0 end
_G.GetVehicleType = function(v) return vehicleType[v] end
_G.GetPedInVehicleSeat = function(v, seat) return seatOf[v .. ':' .. seat] or 0 end
for _, f in ipairs({ 'core', 'cuff', 'escort', 'seize', 'rob', 'dispatch', 'evidence', 'fingerprint', 'tracker',
    'impound', 'spikes', 'objects', 'callbacks', 'compat/stash', 'compat/police' }) do
    dofile('server/' .. f .. '.lua')
end

local OFFICER, OFFDUTY, TARGET, CIVILIAN, FAR = 1, 2, 3, 4, 5
handle.addPlayer(OFFICER, { job = { name = 'police', onduty = true, grade = { level = 2 } } })
handle.addPlayer(OFFDUTY, { job = { name = 'police', onduty = false, grade = { level = 2 } } })
handle.addPlayer(TARGET)
handle.addPlayer(CIVILIAN)
handle.addPlayer(FAR)
handle.setCoords(FAR, 500.0, 0.0, 0.0)
local inv = handle.exportImpls.kora_inventory
local registered, opened = {}, {}
inv.RegisterStash = function(id, _, _, _, owner, groups) registered[id] = { owner = owner, groups = groups } end
inv.OpenInventory = function(src, id) opened[#opened + 1] = { src = src, id = id } end
local cb = handle.Kora.callback.registry

h.test('stash/trash open only for on-duty police', function()
    handle.fireEvent('qb-policejob:server:stash', CIVILIAN)
    handle.fireEvent('qb-policejob:server:stash', OFFDUTY)
    handle.fireEvent('qb-policejob:server:trash', CIVILIAN)
    h.assertEqual(#opened, 0)
    handle.fireEvent('qb-policejob:server:stash', OFFICER)
    h.assertEqual(opened[1].id, 'policestash_CID1')
    h.assertEqual(registered['policestash_CID1'].owner, 'CID1')
    handle.fireEvent('qb-policejob:server:trash', OFFICER)
    h.assertEqual(opened[2].id, 'policetrash')
end)

h.test('stash location list, when configured, is enforced', function()
    Config.stash.locations = { { x = 900.0, y = 0.0, z = 0.0 } }
    local before = #opened
    handle.fireEvent('qb-policejob:server:stash', OFFICER)
    h.assertEqual(#opened, before)
    Config.stash.locations = {}
end)

h.test('evidence drawer id is parsed against configured rooms, never passed through', function()
    local before = #opened
    for _, bad in ipairs({ 'policetrash', '9 | Drawer 1', '1 | Drawer 999', '1 | Drawer 0', 5, '1 | Drawer 1; x' }) do
        handle.fireEvent('qb-policejob:server:evidence', OFFICER, bad)
    end
    h.assertEqual(#opened, before)
    handle.fireEvent('qb-policejob:server:evidence', OFFICER, '1 | Drawer 2')
    h.assertEqual(#opened, before) -- not standing at room 1
    handle.setCoords(OFFICER, 442.1722, -996.067, 30.689)
    handle.fireEvent('qb-policejob:server:evidence', OFFICER, '1 | Drawer 2')
    h.assertEqual(opened[#opened].id, '1 | Drawer 2')
    handle.fireEvent('qb-policejob:server:evidence', CIVILIAN, '1 | Drawer 2')
    h.assertEqual(#opened, before + 1)
    handle.setCoords(OFFICER, 0.0, 0.0, 0.0)
end)

h.test('trash is cleared through SetStashItems', function()
    local cleared
    inv.SetStashItems = function(id) cleared = id; return true end
    h.assertTrue(Police.clearTrash())
    h.assertEqual(cleared, 'policetrash')
end)

h.test('spawnObject creates a server-side prop for on-duty police only, capped', function()
    handle.fireEvent('police:server:spawnObject', CIVILIAN, 'cone')
    h.assertEqual(next(Police.objects), nil)
    handle.fireEvent('police:server:spawnObject', OFFICER, 'nonsense')
    handle.fireEvent('police:server:spawnObject', OFFICER, { x = 1 })
    h.assertEqual(next(Police.objects), nil)
    handle.fireEvent('police:server:spawnObject', OFFICER, 'cone')
    local id, entry = next(Police.objects)
    h.assertTrue(id ~= nil)
    h.assertEqual(entry.type, 'cone')
    local placed = handle.lastClient('qbpolice:client:objectPlaced')
    h.assertEqual(placed.target, OFFICER)
    h.assertEqual(handle.lastClient('police:client:spawnObject').args[2], 'cone')
    handle.advanceClock(1000)
    handle.fireEvent('police:server:spawnObject', OFFICER, 'cone')
    h.assertEqual(Police.objectsByOfficer[OFFICER], 2)
    for _ = 1, 30 do handle.advanceClock(1000); handle.fireEvent('police:server:spawnObject', OFFICER, 'barrier') end
    h.assertEqual(Police.objectsByOfficer[OFFICER], Config.objects.maxPerOfficer)
end)

h.test('deleteObject checks duty, id and distance', function()
    local id = next(Police.objects)
    handle.fireEvent('police:server:deleteObject', CIVILIAN, id)
    h.assertTrue(Police.objects[id] ~= nil)
    handle.fireEvent('police:server:deleteObject', OFFICER, 'x')
    h.assertTrue(Police.objects[id] ~= nil)
    handle.setCoords(OFFICER, 50.0, 0.0, 0.0)
    handle.fireEvent('police:server:deleteObject', OFFICER, id)
    h.assertTrue(Police.objects[id] ~= nil, 'out of reach')
    handle.setCoords(OFFICER, 0.0, 0.0, 0.0)
    handle.fireEvent('police:server:deleteObject', OFFICER, id)
    h.assertEqual(Police.objects[id], nil)
    h.assertEqual(handle.lastClient('police:client:removeObject').args[1], id)
    h.assertTrue(Police.deleteNearestObject(OFFICER))
end)

h.test('heli spotlight needs an on-duty officer in a heli seat and a boolean', function()
    local before = #handle.clientEventsFor('heli:client:spotlight')
    handle.fireEvent('heli:server:spotlight', OFFICER, true)
    h.assertEqual(#handle.clientEventsFor('heli:client:spotlight'), before)
    vehicleOf[OFFICER], vehicleType[77] = 77, 'heli'
    vehicleOf[OFFICER] = 77
    handle.fireEvent('heli:server:spotlight', OFFICER, true)
    h.assertEqual(#handle.clientEventsFor('heli:client:spotlight'), before, 'not in a seat')
    seatOf['77:-1'] = OFFICER
    handle.fireEvent('heli:server:spotlight', OFFICER, 'yes')
    h.assertEqual(#handle.clientEventsFor('heli:client:spotlight'), before)
    handle.fireEvent('heli:server:spotlight', OFFICER, true)
    local event = handle.lastClient('heli:client:spotlight')
    h.assertEqual(event.target, -1)
    h.assertEqual(event.args[1], OFFICER)
    h.assertEqual(event.args[2], true)
    vehicleOf[CIVILIAN], seatOf['77:0'] = 77, CIVILIAN
    handle.fireEvent('heli:server:spotlight', CIVILIAN, true)
    h.assertEqual(#handle.clientEventsFor('heli:client:spotlight'), before + 1)
end)

h.test('SetTracker toggles on and off, in reach only', function()
    handle.fireEvent('police:server:SetTracker', CIVILIAN, TARGET)
    h.assertEqual(Police.tracked[TARGET], nil)
    handle.fireEvent('police:server:SetTracker', OFFICER, FAR)
    h.assertEqual(Police.tracked[FAR], nil)
    handle.fireEvent('police:server:SetTracker', OFFICER, TARGET)
    h.assertTrue(Police.tracked[TARGET])
    h.assertEqual(handle.lastClient('police:client:SetTracker').args[1], true)
    h.assertEqual(handle.players[TARGET].data.metadata.tracker, true)
    handle.fireEvent('police:server:SetTracker', OFFICER, TARGET)
    h.assertEqual(Police.tracked[TARGET], nil)
    h.assertEqual(handle.lastClient('police:client:SetTracker').args[1], false)
    h.assertEqual(handle.players[TARGET].data.metadata.tracker, false)
end)

h.test('SendTrackerLocation replies only for a tracked player to an on-duty requester, with server coords', function()
    handle.fireEvent('police:server:SendTrackerLocation', TARGET, { x = 1, y = 1, z = 1 }, OFFICER)
    h.assertEqual(handle.lastClient('police:client:TrackerMessage'), nil)
    Police.setTracker(OFFICER, TARGET, true)
    handle.setCoords(TARGET, 7.0, 8.0, 9.0)
    handle.fireEvent('police:server:SendTrackerLocation', TARGET, { x = 1, y = 1, z = 1 }, CIVILIAN)
    h.assertEqual(handle.lastClient('police:client:TrackerMessage'), nil)
    handle.fireEvent('police:server:SendTrackerLocation', TARGET, { x = 1, y = 1, z = 1 }, OFFICER)
    local event = handle.lastClient('police:client:TrackerMessage')
    h.assertEqual(event.target, OFFICER)
    h.assertEqual(event.args[2].x, 7.0)
    local count = #handle.clientEventsFor('police:client:TrackerMessage')
    handle.fireEvent('police:server:SendTrackerLocation', TARGET, nil, OFFICER)
    h.assertEqual(#handle.clientEventsFor('police:client:TrackerMessage'), count, 'rate limited')
    Police.setTracker(OFFICER, TARGET, false)
    handle.setCoords(TARGET, 0.0, 0.0, 0.0)
end)

h.test('evidence samples need an officer, the matching marker type, reach and a bag', function()
    local bags, added = 1, nil
    inv.RemoveItem = function() if bags > 0 then bags = bags - 1; return true end return false, 'no bag' end
    inv.AddItem = function(_, name, _, _, info) added = { name = name, info = info }; return true end
    handle.fireEvent('evidence:server:CreateBloodDrop', TARGET, { x = 0 }, 'A+')
    local bloodId = next(Police.worldEvidence)
    handle.fireEvent('evidence:server:AddCasingToInventory', OFFICER, bloodId, { label = 'forged' })
    h.assertEqual(added, nil, 'wrong type')
    handle.fireEvent('evidence:server:AddBlooddropToInventory', CIVILIAN, bloodId)
    h.assertEqual(added, nil)
    handle.fireEvent('evidence:server:AddBlooddropToInventory', OFFICER, bloodId, { label = 'forged', type = 'x' })
    h.assertEqual(added.name, 'filled_evidence_bag')
    h.assertEqual(added.info.type, 'blood')
    h.assertEqual(added.info.label, 'Blood Sample')
    h.assertEqual(Police.worldEvidence[bloodId], nil)
    handle.advanceClock(1000)
    handle.fireEvent('evidence:server:CreateFingerDrop', TARGET, { x = 0 })
    local fingerId = next(Police.worldEvidence)
    handle.fireEvent('evidence:server:AddFingerprintToInventory', OFFICER, fingerId)
    h.assertEqual(Police.worldEvidence[fingerId], Police.worldEvidence[fingerId], 'bag used up, still there')
    h.assertTrue(Police.worldEvidence[fingerId] ~= nil, 'no bag left: marker stays')
end)

h.test('ClearBlooddrops/ClearCasings remove only nearby markers of that type, by police', function()
    for id in pairs(Police.worldEvidence) do Police.worldEvidence[id] = nil end
    handle.advanceClock(1000)
    handle.fireEvent('evidence:server:CreateBloodDrop', TARGET)
    local bloodId = next(Police.worldEvidence)
    handle.advanceClock(1000)
    handle.fireEvent('evidence:server:CreateCasing', TARGET)
    local casingId
    for id, marker in pairs(Police.worldEvidence) do if marker.type == 'casing' then casingId = id end end
    handle.fireEvent('evidence:server:ClearBlooddrops', CIVILIAN, { bloodId })
    h.assertTrue(Police.worldEvidence[bloodId] ~= nil)
    handle.fireEvent('evidence:server:ClearBlooddrops', OFFICER, { casingId, 'x', bloodId })
    h.assertEqual(Police.worldEvidence[bloodId], nil)
    h.assertTrue(Police.worldEvidence[casingId] ~= nil, 'type must match')
    handle.fireEvent('evidence:server:ClearCasings', OFFICER, 'notalist')
    handle.fireEvent('evidence:server:ClearCasings', OFFICER, { casingId })
    h.assertEqual(Police.worldEvidence[casingId], nil)
end)

h.test('UpdateStatus keeps only known ids with server labels; GetPlayerStatus returns the stock text list', function()
    handle.fireEvent('evidence:server:UpdateStatus', TARGET, { alcohol = { text = 'forged', time = 1 }, hax = { text = 'x' } })
    local list = cb['police:GetPlayerStatus'](OFFICER, TARGET)
    h.assertEqual(#list, 1)
    h.assertEqual(list[1], 'Smells like alcohol')
    h.assertEqual(#cb['police:GetPlayerStatus'](CIVILIAN, TARGET), 0)
    h.assertEqual(#cb['police:GetPlayerStatus'](OFFICER, FAR), 0, 'out of reach')
    h.assertEqual(cb['qbpolice:server:getPlayerStatus'](OFFICER, TARGET).status[1], 'Smells like alcohol')
    handle.advanceClock(Config.evidence.statusTtl + 1)
    h.assertEqual(#cb['police:GetPlayerStatus'](OFFICER, TARGET), 0, 'expires')
end)

h.test('Impound maps price to the fee, caps it, ignores client condition values', function()
    local impounded
    handle.exportImpls.kora_core.impound = function(plate, fee, lot) impounded = { plate = plate, fee = fee, lot = lot }; return true end
    _G.GetAllVehicles = function() return { 701 } end
    _G.GetVehicleNumberPlateText = function() return 'ABC123 ' end
    local exists = _G.DoesEntityExist
    _G.DoesEntityExist = function(e) return e == 701 or exists(e) end
    local coords = _G.GetEntityCoords
    _G.GetEntityCoords = function(e) if e == 701 then return handle.vec3(1.0, 0.0, 0.0) end return coords(e) end
    handle.fireEvent('police:server:Impound', CIVILIAN, 'ABC123', false, 100)
    h.assertEqual(impounded, nil)
    handle.fireEvent('police:server:Impound', OFFICER, ' ABC123 ', false, 99999999, 1, 1, 1)
    h.assertEqual(impounded.plate, 'ABC123')
    h.assertEqual(impounded.fee, Config.impound.maxFee)
    impounded = nil
    handle.fireEvent('police:server:Impound', OFFICER, 'ABC123', true, 5)
    h.assertEqual(impounded.fee, Config.impound.fee)
    h.assertTrue(Police.impoundedPlates['ABC123'].full)
    h.assertEqual(handle.exportImpls.kora_core.getByPlate('ABC123'), nil)
end)

h.test('TakeOutImpound needs the lot index in reach and goes through the owner-only retrieval', function()
    local retrieved
    handle.exportImpls.kora_core.getByPlate = function() return { state = 'impounded', impound_fee = 0 } end
    handle.exportImpls.kora_core.retrieveImpound = function(src, plate) retrieved = { src = src, plate = plate }; return true end
    handle.fireEvent('police:server:TakeOutImpound', CIVILIAN, 'ABC123', 1)
    h.assertEqual(retrieved, nil, 'not at the lot')
    handle.setCoords(CIVILIAN, 408.0, -1626.0, 29.3)
    handle.fireEvent('police:server:TakeOutImpound', CIVILIAN, 'ABC123', 9)
    h.assertEqual(retrieved, nil, 'unknown lot')
    handle.fireEvent('police:server:TakeOutImpound', CIVILIAN, 'ABC123', 1)
    h.assertEqual(retrieved.src, CIVILIAN)
end)

h.test('RobPlayer takes cash and opens the inventory only for a restrained or downed target in reach', function()
    handle.setCoords(CIVILIAN, 0.0, 0.0, 0.0)
    local before = #handle.clientEventsFor('qbpolice:client:openRob')
    handle.fireEvent('police:server:RobPlayer', CIVILIAN, TARGET)
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:openRob'), before)
    handle.players[TARGET].data.metadata.isdead = true
    handle.fireEvent('police:server:RobPlayer', CIVILIAN, FAR)
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:openRob'), before)
    local cash = handle.players[TARGET].data.money.cash
    handle.fireEvent('police:server:RobPlayer', CIVILIAN, TARGET)
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:openRob'), before + 1)
    h.assertEqual(handle.lastClient('qbpolice:client:openRob').args[1], TARGET)
    h.assertTrue(Police.hasRobAccess(CIVILIAN, TARGET))
    h.assertTrue(handle.players[TARGET].data.money.cash < cash)
    handle.players[TARGET].data.money.cash = 0
    handle.fireEvent('police:server:RobPlayer', CIVILIAN, TARGET)
    h.assertEqual(#handle.clientEventsFor('qbpolice:client:openRob'), before + 2, 'inventory opens even without cash')
    handle.players[TARGET].data.metadata.isdead = nil
end)

h.report('stock_server_parity')
