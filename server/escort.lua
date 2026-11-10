-- Escort (walk a cuffed suspect), kidnap/drag (move a downed/cuffed player),
-- and put-in/out-of-vehicle. All three are validated server-side and then
-- relayed to the AFFECTED player's own client, which is the one that
-- actually attaches its own networked ped -- see client/escort.lua's header
-- for why this can't be done with Kora.anim.attachProp (that's for props the
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
    TriggerClientEvent('kora_police:client:escortStart', targetSrc, officerSrc)
    TriggerClientEvent('kora_police:client:escortStartSelf', officerSrc, targetSrc)
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
    TriggerClientEvent('kora_police:client:escortStop', targetSrc)
    TriggerClientEvent('kora_police:client:escortStopSelf', officer, targetSrc)
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
    if Police.isCuffed(draggerSrc) then return false, 'you are restrained' end
    if not exports.kora_core:getPlayerData(targetSrc) then return false, 'target not found' end
    if Police.kidnapped[targetSrc] then return false, 'already being dragged' end
    if Police.escorted[targetSrc] then return false, 'target is being escorted' end
    if Police.distanceBetween(draggerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end
    if not Police.isIncapacitated(targetSrc) then return false, 'target is not restrained or down' end

    Police.kidnapped[targetSrc] = draggerSrc
    TriggerClientEvent('kora_police:client:dragStart', targetSrc, draggerSrc)
    TriggerClientEvent('kora_police:client:dragStartSelf', draggerSrc, targetSrc)
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
    TriggerClientEvent('kora_police:client:dragStop', targetSrc)
    TriggerClientEvent('kora_police:client:dragStopSelf', dragger, targetSrc)
    return true
end

local function pedInVehicle(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or type(GetVehiclePedIsIn) ~= 'function' then return false end
    local vehicle = GetVehiclePedIsIn(ped, false)
    return vehicle ~= nil and vehicle ~= 0
end

---Why a drag should end right now, or nil to keep it going.
---@param draggerSrc integer
---@param targetSrc integer
---@return string|nil
local function dragReleaseReason(draggerSrc, targetSrc)
    local cfg = Config.drag or {}
    if not exports.kora_core:getPlayerData(draggerSrc) or not exports.kora_core:getPlayerData(targetSrc) then
        return 'player left'
    end
    if Police.distanceBetween(draggerSrc, targetSrc) > (tonumber(cfg.autoReleaseDistance) or 8.0) then return 'too far away' end
    if Police.isDowned(draggerSrc) then return 'dragger is down' end
    if cfg.releaseInVehicle ~= false and (pedInVehicle(draggerSrc) or pedInVehicle(targetSrc)) then return 'entered a vehicle' end
    if cfg.releaseWhenRecovered ~= false and not Police.isIncapacitated(targetSrc) then return 'target is no longer restrained or down' end
    return nil
end

---Releases every drag whose dragger died, moved away, entered a vehicle,
---disconnected, or whose target recovered. Run by the sweep thread below.
function Police.sweepDrags()
    for target, dragger in pairs(Police.kidnapped) do
        if dragReleaseReason(dragger, target) then Police.stopDrag(dragger, target) end
    end
end

CreateThread(function()
    while true do
        Wait(math.max(250, tonumber((Config.drag or {}).checkInterval) or 1000))
        Police.sweepDrags()
    end
end)

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
    if type(netId) ~= 'number' or netId <= 0 or netId % 1 ~= 0 then return false, 'vehicle not found' end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'vehicle not found' end

    Police.deEscort(officerSrc, targetSrc)
    Police.stopDrag(officerSrc, targetSrc)
    TriggerClientEvent('kora_police:client:putInVehicle', targetSrc, netId, seat or -1)
    return true
end

---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.takeOutVehicle(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if not Police.isCuffed(targetSrc) then return false, 'target is not cuffed' end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end

    TriggerClientEvent('kora_police:client:takeOutVehicle', targetSrc)
    return true
end

RegisterNetEvent('kora_police:server:escort', function(target)
    local ok, err = Police.escort(source, tonumber(target))
    if not ok then Police.notify(source, err) end
end)
RegisterNetEvent('kora_police:server:deEscort', function(target)
    local ok, err = Police.deEscort(source, tonumber(target))
    if not ok then Police.notify(source, err) end
end)
RegisterNetEvent('kora_police:server:startDrag', function(target)
    local ok, err = Police.startDrag(source, tonumber(target))
    if not ok then Police.notify(source, err) end
end)
RegisterNetEvent('kora_police:server:stopDrag', function(target)
    local src = source
    target = tonumber(target)
    -- The client's idea of who it drags can be stale (or the server already
    -- released): fall back to whoever the server says this player drags, and
    -- when nothing is dragged tell the client to drop its stale state instead
    -- of leaving it stuck on a release that can never succeed.
    if not (target and Police.kidnapped[target]) then target = Police.getKidnappedTarget(src) or target end
    local ok, err = Police.stopDrag(src, target)
    if ok then return end
    if err == 'not being dragged' then
        TriggerClientEvent('kora_police:client:dragStopSelf', src, target)
        return
    end
    Police.notify(src, err)
end)
RegisterNetEvent('kora_police:server:putInVehicle', function(target, netId, seat)
    local ok, err = Police.putInVehicle(source, tonumber(target), tonumber(netId), seat and tonumber(seat) or nil)
    if not ok then Police.notify(source, err) end
end)
RegisterNetEvent('kora_police:server:takeOutVehicle', function(target)
    local ok, err = Police.takeOutVehicle(source, tonumber(target))
    if not ok then Police.notify(source, err) end
end)
