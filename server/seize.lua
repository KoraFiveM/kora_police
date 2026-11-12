-- Search a cuffed suspect and seize cash/items. Wired directly onto
-- kora_inventory's existing player-inspection seam (`RegisterInspectionAccess`)
-- rather than any new inventory code: granting inspection makes the target's
-- own inventory the officer's session secondary, so the officer's existing
-- client inventory UI can drag items out (into their own pockets, or -- via
-- the evidence locker stash registered in server/evidence.lua -- into
-- evidence) using kora_inventory's normal, already-tested transfer protocol.

CreateThread(function()
    exports.kora_inventory:registerInspectionAccess(function(src, target)
        -- A successful Police.rob (server/rob.lua) grants the robber access
        -- while the target stays restrained/downed and in range.
        if Police.hasRobAccess and Police.hasRobAccess(src, target) then return true end
        if not Police.isPolice(src) then return false, Kora.lang('Notify.on_duty_police') end
        if not Police.isCuffed(target) then return false, Kora.lang('Notify.target_is_not_restrained') end
        return true
    end)
end)

---Validates the search request, then tells the OFFICER's own client to open
---the target's inventory -- `exports.kora_inventory:openInventory` is a
---client-realm export (it just fires the `kora_inventory:server:open` net
---event), so this can't be called from here; kora_inventory's own
---`registerInspectionAccess` policy above re-checks the same conditions
---server-side regardless of what the client requests.
---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.search(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, Kora.lang('Notify.on_duty_police') end
    if not Police.isCuffed(targetSrc) then return false, Kora.lang('Notify.target_is_not_restrained') end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, Kora.lang('Notify.too_far_away') end
    TriggerClientEvent('kora_police:client:openSearch', officerSrc, targetSrc)
    TriggerClientEvent('police:client:SearchPlayer', officerSrc, targetSrc)
    return true
end

---Legacy `SeizeCash` -- moves every account balance the suspect is carrying
---as physical cash into the officer's own cash account.
---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil, number|nil seized
function Police.seizeCash(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, Kora.lang('Notify.on_duty_police') end
    if not Police.isCuffed(targetSrc) then return false, Kora.lang('Notify.target_is_not_restrained') end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, Kora.lang('Notify.too_far_away') end

    local amount = exports.kora_core:getMoney(targetSrc, 'cash') or 0
    if amount <= 0 then return false, Kora.lang('Notify.target_has_no_cash') end

    local transferred, transferErr = exports.kora_core:transferMoney(targetSrc, officerSrc, 'cash', amount, 'evidence-cash-seizure')
    if not transferred then return false, transferErr or 'could not seize cash' end
    return true, nil, amount
end

---Legacy `SeizeDriverLicense` -- flags the suspect's license metadata as
---confiscated (mirrors qb-policejob's use of the `metadata.licences` table).
---@param officerSrc integer
---@param targetSrc integer
---@return boolean, string|nil
function Police.seizeDriverLicense(officerSrc, targetSrc)
    if not Police.isPolice(officerSrc) then return false, Kora.lang('Notify.on_duty_police') end
    if not Police.isCuffed(targetSrc) then return false, Kora.lang('Notify.target_is_not_restrained') end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, Kora.lang('Notify.too_far_away') end

    local licences = exports.kora_core:getMetaData(targetSrc, 'licences') or {}
    licences = type(licences) == 'table' and licences or {}
    licences.driver = false
    exports.kora_core:setMetaData(targetSrc, 'licences', licences)
    return true
end

RegisterNetEvent('kora_police:server:search', function(target)
    local ok, err = Police.search(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('kora_police:server:seizeCash', function(target)
    local ok, err, amount = Police.seizeCash(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error')
    else TriggerClientEvent('QBCore:Notify', source, ('Seized $%d in cash.'):format(amount), 'success') end
end)
RegisterNetEvent('kora_police:server:seizeDriverLicense', function(target)
    local ok, err = Police.seizeDriverLicense(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
