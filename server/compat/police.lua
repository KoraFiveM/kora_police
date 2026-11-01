-- Every `police:server:*`/`police:client:*`/`evidence:server:*` legacy event
-- name from the plan's backwards-compat checklist, forwarding onto the
-- Police.* functions defined in the sibling server/*.lua files. Kept as one
-- file (matches kora_inventory's own server/compat/qb.lua convention) so the
-- full legacy surface is auditable in one place against that checklist.
--
-- Deliberately NOT preserved (per the plan): `qb-policejob:server:stash/
-- trash/evidence` -- replaced by calling kora_inventory's stash/evidence
-- functions directly, since this framework's kora_inventory is the real
-- authority already. Deliberately deferred: `heli:server/client:spotlight`.

local function notify(src, err)
    if err then TriggerClientEvent('QBCore:Notify', src, err, 'error') end
end

-- Stock's second argument (isSoftcuff) only picks the cuffed animation; kora's
-- "soft" cuff is the escapable handcuffs-item flow, so it is deliberately
-- ignored and an officer's cuff is always the unescapable one.
RegisterNetEvent('police:server:CuffPlayer', function(target)
    notify(source, select(2, Police.cuff(source, tonumber(target))))
end)
RegisterNetEvent('police:server:CuffPlayerSoft', function()
    notify(source, select(2, Police.softCuffNearby(source)))
end)
-- Stock sends a BOOLEAN from the cuffed player's own client ("I am / am no
-- longer handcuffed") so the server can mirror it into metadata. Kora owns that
-- state, so a client claim never changes it: the caller is just re-sent the
-- authoritative state. The older `(target, cuffed)` officer form still goes
-- through Police.cuff/uncuff and their checks.
RegisterNetEvent('police:server:SetHandcuffStatus', function(target, cuffed)
    local src = source
    if type(target) == 'boolean' or target == nil then
        local state = Police.cuffState[src]
        TriggerClientEvent('qbpolice:client:cuffed', src, Police.isCuffed(src), state ~= nil and state.soft or false)
        return
    end
    local targetSrc = tonumber(target)
    if not targetSrc then return end
    if cuffed then notify(src, select(2, Police.cuff(src, targetSrc)))
    else notify(src, select(2, Police.uncuff(src, targetSrc))) end
end)
Kora.callback.register('police:GetCuffed', function(src, target)
    return Police.isCuffed(target or src)
end)

RegisterNetEvent('police:server:SearchPlayer', function(target)
    notify(source, select(2, Police.search(source, tonumber(target))))
end)
RegisterNetEvent('police:server:SeizeCash', function(target)
    local ok, err, amount = Police.seizeCash(source, tonumber(target))
    if ok then TriggerClientEvent('QBCore:Notify', source, ('Seized $%d in cash.'):format(amount), 'success')
    else notify(source, err) end
end)
RegisterNetEvent('police:server:SeizeDriverLicense', function(target)
    notify(source, select(2, Police.seizeDriverLicense(source, tonumber(target))))
end)

RegisterNetEvent('police:server:EscortPlayer', function(target)
    notify(source, select(2, Police.escort(source, tonumber(target))))
end)
RegisterNetEvent('police:server:DeEscort', function(target)
    notify(source, select(2, Police.deEscort(source, tonumber(target) or source)))
end)
Kora.callback.register('police:GetEscorted', function(src, target)
    return Police.getEscorted(target or src)
end)

RegisterNetEvent('police:server:KidnapPlayer', function(target)
    notify(source, select(2, Police.startDrag(source, tonumber(target))))
end)
Kora.callback.register('police:GetKidnappedTarget', function(src)
    return Police.getKidnappedTarget(src)
end)
Kora.callback.register('police:GetKidnappedDragger', function(src, target)
    return Police.getKidnappedDragger(target or src)
end)

-- Stock sends only the target and lets the server choose the vehicle. Kora's
-- native flow names the vehicle; here the nearest one to the officer is used.
local VEHICLE_REACH = 5.0
local function nearestVehicleNetId(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local origin = GetEntityCoords(ped)
    local best, bestDistance
    for _, vehicle in ipairs(GetAllVehicles()) do
        local distance = #(GetEntityCoords(vehicle) - origin)
        if distance <= VEHICLE_REACH and (not bestDistance or distance < bestDistance) then
            best, bestDistance = vehicle, distance
        end
    end
    return best and NetworkGetNetworkIdFromEntity(best) or nil
end

local function putInVehicle(src, target, netId, seat)
    netId = tonumber(netId) or nearestVehicleNetId(src)
    notify(src, select(2, Police.putInVehicle(src, tonumber(target), netId, seat and tonumber(seat) or nil)))
end
RegisterNetEvent('police:server:PutPlayerInVehicle', function(target, netId, seat) putInVehicle(source, target, netId, seat) end)
RegisterNetEvent('police:server:PutInVehicle', function(target, netId, seat) putInVehicle(source, target, netId, seat) end)
RegisterNetEvent('police:server:SetPlayerOutVehicle', function(target)
    notify(source, select(2, Police.takeOutVehicle(source, tonumber(target))))
end)
RegisterNetEvent('police:server:SetOutVehicle', function(target)
    notify(source, select(2, Police.takeOutVehicle(source, tonumber(target))))
end)

RegisterNetEvent('police:server:BillPlayer', function(target, amount, reason)
    notify(source, select(2, Police.bill(source, tonumber(target), amount, reason)))
end)
RegisterNetEvent('police:server:JailPlayer', function(target, minutes, reason)
    notify(source, select(2, Police.jailPlayer(source, tonumber(target), minutes, reason)))
end)
RegisterNetEvent('police:server:SendToJail', function(target, minutes, reason)
    notify(source, select(2, Police.jailPlayer(source, tonumber(target), minutes, reason)))
end)
RegisterNetEvent('police:server:RobPlayer', function(target)
    local ok, err, amount = Police.rob(source, tonumber(target))
    if ok then TriggerClientEvent('QBCore:Notify', source, ('You took $%d.'):format(amount), 'success')
    else notify(source, err) end
end)

-- Each of these fans out to every client, and any client can fire them, so they
-- share one throttle PER SOURCE (stock has a re-entrancy guard for the same
-- reason), so one spamming client cannot starve the others' refreshes.
local lastCopCountBroadcast = {}
local function throttledCopCount()
    local src = tonumber(source)
    if not src or src <= 0 then return end
    local now = GetGameTimer()
    local last = lastCopCountBroadcast[src]
    if last and now - last < Config.dispatch.copCountThrottle then return end
    lastCopCountBroadcast[src] = now
    Police.broadcastCopCount()
end
AddEventHandler('playerDropped', function() lastCopCountBroadcast[source] = nil end)
RegisterNetEvent('police:server:UpdateCurrentCops', throttledCopCount)
RegisterNetEvent('police:server:SetCopCount', throttledCopCount)
RegisterNetEvent('police:server:UpdateBlips', throttledCopCount)

-- Stock `police:server:policeAlert(text)`: anyone can raise a police call at
-- their own position (qb-vehiclekeys does, on a theft). Position is read from
-- the caller's ped, never from the client; text is sanitised and length-capped;
-- one call per player per Config.dispatch.legacyAlertCooldown. The same-server
-- TriggerEvent kora_core fires with this name has no player source and is
-- ignored, as is anything re-entering while a call is being created, so the
-- dispatch mirror cannot loop back into itself.
--
-- kora_core fires that local TriggerEvent from inside Core.dispatch.alert, and
-- when the alert was itself raised from a net-event handler `source` is still
-- that player, so the missing source is not a reliable marker. Core.dispatch.alert
-- first fires the server-only `qbcore:server:dispatchAlert` with the same
-- payload; its message is remembered here for MIRROR_WINDOW_MS and the next
-- policeAlert carrying exactly that text is treated as the mirror and dropped.
local MIRROR_WINDOW_MS = 1000
local mirroredMessages = {}
AddEventHandler('qbcore:server:dispatchAlert', function(payload)
    if type(payload) ~= 'table' then return end
    local message = payload.message or payload.title or ''
    if type(message) ~= 'string' then return end
    mirroredMessages[message] = GetGameTimer() + MIRROR_WINDOW_MS
end)
local function isDispatchMirror(text)
    local expires = mirroredMessages[text]
    if not expires then return false end
    mirroredMessages[text] = nil
    return GetGameTimer() <= expires
end

local lastLegacyAlertAt = {}
local raisingLegacyAlert = false
RegisterNetEvent('police:server:policeAlert', function(text)
    local src = tonumber(source)
    if raisingLegacyAlert or not src or src <= 0 or not exports.kora_core:getPlayerData(src) then return end
    if type(text) ~= 'string' then return end
    if isDispatchMirror(text) then return end
    text = text:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, Config.dispatch.legacyAlertMaxLength)
    if text == '' then return end

    local now = GetGameTimer()
    local last = lastLegacyAlertAt[src]
    if last and now - last < Config.dispatch.legacyAlertCooldown then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    lastLegacyAlertAt[src] = now

    local position = GetEntityCoords(ped)
    raisingLegacyAlert = true
    local ok, err = pcall(Police.dispatch, {
        code = '10-60', title = 'Police Alert', message = text, priority = 2, icon = 'siren',
        coords = { x = position.x, y = position.y, z = position.z },
        data = { reporter = src, legacy = true },
    })
    raisingLegacyAlert = false
    if not ok then print(('^3[qbpolice]^7 police:server:policeAlert failed: %s'):format(err)) end
end)
AddEventHandler('playerDropped', function() lastLegacyAlertAt[source] = nil end)

RegisterNetEvent('police:server:showFingerprint', function(target)
    local fingerprint = Police.getFingerprintForOfficer(source, target)
    if fingerprint then TriggerClientEvent('police:client:showFingerprint', source, fingerprint) end
end)
RegisterNetEvent('police:server:showFingerprintId', function(target)
    local fingerprint = Police.getFingerprintForOfficer(source, target)
    if fingerprint then TriggerClientEvent('police:client:showFingerprintId', source, fingerprint) end
end)

RegisterNetEvent('police:server:SetTracker', function(target)
    Police.setTracker(source, tonumber(target), true)
end)
RegisterNetEvent('police:server:TrackerMessage', function(target, message)
    if not Police.isPolice(source) then return end
    target = tonumber(target)
    if not target or Police.tracked[target] ~= true then return end
    if type(message) ~= 'string' then return end
    message = message:sub(1, 160)
    for _, officer in ipairs(exports.kora_core:getPlayersByJob(Config.police.job, true)) do
        TriggerClientEvent('police:client:TrackerMessage', officer, target, message)
    end
end)

-- Stock sends (coords, plate); see Police.legacyFlaggedPlate for the checks.
local lastFlaggedPlateAt = {}
RegisterNetEvent('police:server:FlaggedPlateTriggered', function(coords, plate)
    local src = source
    local now = GetGameTimer()
    if lastFlaggedPlateAt[src] and now - lastFlaggedPlateAt[src] < 1000 then return end
    lastFlaggedPlateAt[src] = now
    Police.legacyFlaggedPlate(src, coords, plate)
end)
AddEventHandler('playerDropped', function() lastFlaggedPlateAt[source] = nil end)

RegisterNetEvent('police:server:Impound', function(plate) Police.impound(source, plate) end)
RegisterNetEvent('police:server:TakeOutImpound', function(plate) Police.retrieveImpound(source, plate) end)

RegisterNetEvent('police:server:spawnObject', function(coords)
    Police.deploySpike(source, coords)
end)
RegisterNetEvent('police:server:SyncSpikes', function(netId, active)
    local id = tonumber(netId)
    local entry = id and Police.spikes[id]
    -- Deployment is always server-created through spawnObject/deploySpike.
    -- The only safe legacy sync request is the owning officer removing a
    -- strip the server still tracks; Police.removeSpike performs the fanout.
    if active == false and entry and entry.officer == source then Police.removeSpike(id) end
end)
