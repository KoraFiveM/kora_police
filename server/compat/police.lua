-- Every `police:server:*`/`police:client:*`/`evidence:server:*` legacy event
-- name from the plan's backwards-compat checklist, forwarding onto the
-- Police.* functions defined in the sibling server/*.lua files. Kept as one
-- file (matches qbinventory's own server/compat/qb.lua convention) so the
-- full legacy surface is auditable in one place against that checklist.
--
-- Deliberately NOT preserved (per the plan): `qb-policejob:server:stash/
-- trash/evidence` -- replaced by calling qbinventory's stash/evidence
-- functions directly, since this framework's qbinventory is the real
-- authority already. Deliberately deferred: `heli:server/client:spotlight`.

local function notify(src, err)
    if err then TriggerClientEvent('QBCore:Notify', src, err, 'error') end
end

-- Cuff / restrain -------------------------------------------------------

RegisterNetEvent('police:server:CuffPlayer', function(target)
    notify(source, select(2, Police.cuff(source, tonumber(target))))
end)
RegisterNetEvent('police:server:CuffPlayerSoft', function()
    notify(source, select(2, Police.softCuffNearby(source)))
end)
RegisterNetEvent('police:server:SetHandcuffStatus', function(target, cuffed)
    local targetSrc = tonumber(target) or source
    if cuffed then notify(source, select(2, Police.cuff(source, targetSrc)))
    else notify(source, select(2, Police.uncuff(source, targetSrc))) end
end)
QB.callback.register('police:GetCuffed', function(src, target)
    return Police.isCuffed(target or src)
end)

-- Search / seize ----------------------------------------------------------

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

-- Escort / drag / vehicle --------------------------------------------------

RegisterNetEvent('police:server:EscortPlayer', function(target)
    notify(source, select(2, Police.escort(source, tonumber(target))))
end)
RegisterNetEvent('police:server:DeEscort', function(target)
    notify(source, select(2, Police.deEscort(source, tonumber(target) or source)))
end)
QB.callback.register('police:GetEscorted', function(src, target)
    return Police.getEscorted(target or src)
end)

RegisterNetEvent('police:server:KidnapPlayer', function(target)
    notify(source, select(2, Police.startDrag(source, tonumber(target))))
end)
QB.callback.register('police:GetKidnappedTarget', function(src)
    return Police.getKidnappedTarget(src)
end)
QB.callback.register('police:GetKidnappedDragger', function(src, target)
    return Police.getKidnappedDragger(target or src)
end)

RegisterNetEvent('police:server:PutPlayerInVehicle', function(target, netId, seat)
    notify(source, select(2, Police.putInVehicle(source, tonumber(target), tonumber(netId), seat and tonumber(seat) or nil)))
end)
RegisterNetEvent('police:server:PutInVehicle', function(target, netId, seat)
    notify(source, select(2, Police.putInVehicle(source, tonumber(target), tonumber(netId), seat and tonumber(seat) or nil)))
end)
RegisterNetEvent('police:server:SetPlayerOutVehicle', function(target)
    notify(source, select(2, Police.takeOutVehicle(source, tonumber(target))))
end)
RegisterNetEvent('police:server:SetOutVehicle', function(target)
    notify(source, select(2, Police.takeOutVehicle(source, tonumber(target))))
end)

-- Billing / jail / robbery -------------------------------------------------

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

-- Dispatch / cop count / fingerprint / tracker / plates --------------------

RegisterNetEvent('police:server:UpdateCurrentCops', function() Police.broadcastCopCount() end)
RegisterNetEvent('police:server:SetCopCount', function() Police.broadcastCopCount() end)
RegisterNetEvent('police:server:UpdateBlips', function() Police.broadcastCopCount() end)

RegisterNetEvent('police:server:showFingerprint', function(target)
    local targetSrc = tonumber(target) or source
    if not Police.isPolice(source) or Police.distanceBetween(source, targetSrc) > Config.cuff.distance then return end
    local cid = Police.citizenId(targetSrc)
    if not cid then return end
    TriggerClientEvent('police:client:showFingerprint', source, Police.getFingerprint(cid))
end)
RegisterNetEvent('police:server:showFingerprintId', function(target)
    local targetSrc = tonumber(target) or source
    if not Police.isPolice(source) or Police.distanceBetween(source, targetSrc) > Config.cuff.distance then return end
    local cid = Police.citizenId(targetSrc)
    if not cid then return end
    TriggerClientEvent('police:client:showFingerprintId', source, Police.getFingerprint(cid))
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
    for _, officer in ipairs(exports.qbcore:getPlayersByJob(Config.police.job, true)) do
        TriggerClientEvent('police:client:TrackerMessage', officer, target, message)
    end
end)

RegisterNetEvent('police:server:FlaggedPlateTriggered', function(plate)
    Police.triggerFlaggedPlate(source, plate)
end)

-- Impound -------------------------------------------------------------------

RegisterNetEvent('police:server:Impound', function(plate) Police.impound(source, plate) end)
RegisterNetEvent('police:server:TakeOutImpound', function(plate) Police.retrieveImpound(source, plate) end)

-- Spikes ----------------------------------------------------------------

RegisterNetEvent('police:server:spawnObject', function(coords)
    Police.deploySpike(source, coords)
end)
RegisterNetEvent('police:server:SyncSpikes', function(netId, active)
    TriggerClientEvent('police:client:SyncSpikes', -1, tonumber(netId), active)
end)
