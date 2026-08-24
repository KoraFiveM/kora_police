-- Citations/fines and the `moneybag` useable item (cash payout).

---@param officerSrc integer
---@param targetSrc integer
---@param amount number
---@param reason string|nil
---@return boolean, string|nil
function Police.bill(officerSrc, targetSrc, amount, reason)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount <= 0 or amount > 100000 then return false, 'invalid fine amount' end
    if not exports.qbcore:getPlayerData(targetSrc) then return false, 'target not found' end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end

    local removed, err = exports.qbcore:removeMoney(targetSrc, Config.fine.account, amount, reason or 'citation')
    if not removed then
        -- Config.money.allowNegative decides whether this ever actually fails;
        -- surface the underlying reason (e.g. account floor) either way.
        return false, err or 'target could not pay the fine'
    end
    TriggerClientEvent('QBCore:Notify', targetSrc, ('You were fined $%d%s.'):format(amount, reason and (' for ' .. reason) or ''), 'error')
    return true
end

RegisterNetEvent('qbpolice:server:bill', function(target, amount, reason)
    local ok, err = Police.bill(source, tonumber(target), amount, reason)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)

exports.qbcore:createUseable('moneybag', function(src, item)
    local amount = tonumber(item and item.info and item.info.amount) or 0
    local slot = tonumber(item and item.slot)
    if amount ~= math.floor(amount) or amount <= 0 or not slot then return false end
    local removed, removeErr = exports.qbcore:removeItem(src, 'moneybag', 1, slot, 'moneybag-payout')
    if not removed then return false, removeErr end
    local paid, payErr = exports.qbcore:addMoney(src, 'cash', amount, 'moneybag-payout')
    if not paid then
        exports.qbcore:addItem(src, 'moneybag', 1, slot, item.info or {}, 'moneybag-payout-rollback')
        return false, payErr
    end
    TriggerClientEvent('QBCore:Notify', src, ('You deposited $%d in cash.'):format(amount), 'success')
    return true
end)
