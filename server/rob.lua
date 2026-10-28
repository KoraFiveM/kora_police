-- Legacy `RobPlayer` -- a plain player-vs-player cash grab, distinct from
-- `SeizeCash` (which requires the target be restrained by an officer). Kept
-- deliberately simple: distance-checked, capped by Config.fine tiers'
-- largest value so it can't be used to drain an unlimited amount at once.

local MAX_ROB_AMOUNT = 0
for _, tier in ipairs(Config.fine.tiers) do
    if tier[1] > MAX_ROB_AMOUNT then MAX_ROB_AMOUNT = tier[1] end
end
MAX_ROB_AMOUNT = MAX_ROB_AMOUNT * 5

---@param robberSrc integer
---@param targetSrc integer
---@return boolean, string|nil, number|nil
function Police.rob(robberSrc, targetSrc)
    if robberSrc == targetSrc then return false, 'cannot rob yourself' end
    if not exports.kora_core:getPlayerData(targetSrc) then return false, 'target not found' end
    if Police.distanceBetween(robberSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end
    if not Police.isIncapacitated(targetSrc) then return false, 'target is not restrained or down' end

    local available = exports.kora_core:getMoney(targetSrc, 'cash') or 0
    local amount = math.min(available, MAX_ROB_AMOUNT)
    if amount <= 0 then return false, 'target has no cash' end

    local transferred, transferErr = exports.kora_core:transferMoney(targetSrc, robberSrc, 'cash', amount, 'robbery')
    if not transferred then return false, transferErr or 'could not take cash' end
    return true, nil, amount
end

RegisterNetEvent('qbpolice:server:rob', function(target)
    local ok, err, amount = Police.rob(source, tonumber(target))
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error')
    else TriggerClientEvent('QBCore:Notify', source, ('You took $%d.'):format(amount), 'success') end
end)
