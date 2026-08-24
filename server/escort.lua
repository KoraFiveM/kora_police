-- Escort (walk a cuffed suspect), kidnap/drag (move a downed/cuffed player),
-- and put-in/out-of-vehicle. All three are validated server-side and then
-- relayed to the AFFECTED player's own client, which is the one that
-- actually attaches its own networked ped -- see client/escort.lua's header
-- for why this can't be done with QB.anim.attachProp (that's for props the
-- caller owns, not another player's networked ped).

---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.escort(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if not Police.isCuffed(targetSrc) then return false, 'target is not cuffed' end
    if Police.escorted[targetSrc] then return false, 'already being escorted' end
    if Police.kidnapped[targetSrc] then return false, 'target is being dragged' end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end

    Police.escorted[targetSrc] = officerSrc
    TriggerClientEvent('qbpolice:client:escortStart', targetSrc, officerSrc)
    TriggerClientEvent('qbpolice:client:escortStartSelf', officerSrc, targetSrc)
    return true
end

---@param requesterSrc integer Officer or the escorted player themself (breaking free is handled by the cuff system, not here).
---@param targetSrc integer
---@return boolean, string|nil
function Police.deEscort(requesterSrc, targetSrc)
    local officer = Police.escorted[targetSrc]
    if not officer then return false, 'not being escorted' end
    if requesterSrc ~= officer and requesterSrc ~= targetSrc then return false, 'not authorised' end

    Police.escorted[targetSrc] = nil
    TriggerClientEvent('qbpolice:client:escortStop', targetSrc)
    TriggerClientEvent('qbpolice:client:escortStopSelf', officer, targetSrc)
    return true
end

---@return integer|nil officerSrc
function Police.getEscorted(targetSrc)
    return Police.escorted[targetSrc]
end

---Drag (kidnap-style) a downed or cuffed player. Distinct relationship from
---escort -- a dragged player is typically unconscious and cannot walk under
---their own power, so the dragger's client carries more of the position sync.
---@param draggerSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.startDrag(draggerSrc, targetSrc)
    if draggerSrc == targetSrc then return false, 'cannot drag yourself' end
    if not exports.qbcore:getPlayerData(targetSrc) then return false, 'target not found' end
    if Police.kidnapped[targetSrc] then return false, 'already being dragged' end
    if Police.escorted[targetSrc] then return false, 'target is being escorted' end
    if Police.distanceBetween(draggerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end
    if not Police.isIncapacitated(targetSrc) then return false, 'target is not restrained or down' end

    Police.kidnapped[targetSrc] = draggerSrc
    TriggerClientEvent('qbpolice:client:dragStart', targetSrc, draggerSrc)
    TriggerClientEvent('qbpolice:client:dragStartSelf', draggerSrc, targetSrc)
    return true
end

---@param requesterSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.stopDrag(requesterSrc, targetSrc)
    local dragger = Police.kidnapped[targetSrc]
    if not dragger then return false, 'not being dragged' end
    if requesterSrc ~= dragger and requesterSrc ~= targetSrc then return false, 'not authorised' end

    Police.kidnapped[targetSrc] = nil
    TriggerClientEvent('qbpolice:client:dragStop', targetSrc)
    TriggerClientEvent('qbpolice:client:dragStopSelf', dragger, targetSrc)
    return true
end

function Police.getKidnappedTarget(draggerSrc)
    for target, dragger in pairs(Police.kidnapped) do
        if dragger == draggerSrc then return target end
    end
    return nil
end

function Police.getKidnappedDragger(targetSrc)
    return Police.kidnapped[targetSrc]
end

---Put a cuffed suspect into a vehicle seat, or take them back out. `seat`
---matches the native VehicleSeat enum (-1 driver, 0+ passenger).
---@param officerSrc integer
---@param targetSrc integer
---@param netId integer Vehicle network id.
---@param seat integer|nil
---@return boolean, string|nil
function Police.putInVehicle(officerSrc, targetSrc, netId, seat)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if not Police.isCuffed(targetSrc) then return false, 'target is not cuffed' end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end
    if not netId or not NetworkDoesNetworkIdExist(netId) then return false, 'vehicle not found' end

    Police.deEscort(officerSrc, targetSrc)
    Police.stopDrag(officerSrc, targetSrc)
    TriggerClientEvent('qbpolice:client:putInVehicle', targetSrc, netId, seat or -1)
    return true
end

---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.takeOutVehicle(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if not Police.isCuffed(targetSrc) then return false, 'target is not cuffed' end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end

    TriggerClientEvent('qbpolice:client:takeOutVehicle', targetSrc)
    return true
end

RegisterNetEvent('qbpolice:server:escort', function(target)
    local ok, err = Police.escort(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:deEscort', function(target)
    local ok, err = Police.deEscort(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:startDrag', function(target)
    local ok, err = Police.startDrag(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:stopDrag', function(target)
    local ok, err = Police.stopDrag(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:putInVehicle', function(target, netId, seat)
    local ok, err = Police.putInVehicle(source, tonumber(target), tonumber(netId), seat and tonumber(seat) or nil)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:takeOutVehicle', function(target)
    local ok, err = Police.takeOutVehicle(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
