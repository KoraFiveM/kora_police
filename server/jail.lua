-- Thin wrapper over kora_core's Core.jail (exports.kora_core:jailPlayer). Adds
-- nothing to the jail mechanism itself -- teleport/timer/persistence and the
-- external-prison-resource deference all already live in kora_core -- this file
-- only adds the police-specific bookkeeping (officer authority, minutes
-- default, and clearing cuff/escort/drag state on booking).

---@param officerSrc integer
---@param targetSrc integer
---@param minutes number|nil
---@param reason string|nil
---@return boolean, string|nil
function Police.jailPlayer(officerSrc, targetSrc, minutes, reason)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if not exports.kora_core:getPlayerData(targetSrc) then return false, 'target not found' end

    minutes = tonumber(minutes) or Config.jail.defaultMinutes
    local ok, err = exports.kora_core:jailPlayer(targetSrc, minutes, reason)
    if not ok then return false, err end

    Police.deEscort(officerSrc, targetSrc)
    Police.stopDrag(officerSrc, targetSrc)
    -- Taken into custody, not freed: no uncuff animation or "you are free" notification.
    Police.uncuff(officerSrc, targetSrc, { silent = true })
    return true
end

RegisterNetEvent('qbpolice:server:jailPlayer', function(target, minutes, reason)
    local ok, err = Police.jailPlayer(source, tonumber(target), minutes, reason)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
