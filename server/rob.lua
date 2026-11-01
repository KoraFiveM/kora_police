-- Legacy `RobPlayer` -- a plain player-vs-player robbery, distinct from
-- `SeizeCash` (which requires the target be restrained by an officer). Takes
-- the target's cash (capped by Config.fine.tiers' largest value so it can't
-- drain an unlimited amount at once) and/or opens the target's inventory as
-- the robber's secondary inventory, per Config.rob.
--
-- kora_inventory only lets a player open another player's inventory when a
-- trusted server policy grants it (`registerInspectionAccess`, see
-- server/seize.lua). A successful rob records a short-lived grant here that
-- policy consults; the grant is re-validated (target still restrained/downed,
-- still in range) on every inventory request AND by a sweep that closes the
-- robber's inventory when the target gets up or moves away.

local MAX_ROB_AMOUNT = 0
for _, tier in ipairs(Config.fine.tiers) do
    if tier[1] > MAX_ROB_AMOUNT then MAX_ROB_AMOUNT = tier[1] end
end
MAX_ROB_AMOUNT = MAX_ROB_AMOUNT * 5

-- [robberSrc] = { target = src, expires = gameTimer ms, opened = bool }
Police.robGrants = Police.robGrants or {}

local function robConfig()
    return Config.rob or {}
end

local function robStillValid(robberSrc, targetSrc)
    if not exports.kora_core:getPlayerData(targetSrc) then return false end
    if not Police.isIncapacitated(targetSrc) then return false end
    local limit = tonumber(robConfig().closeDistance) or Config.cuff.distance
    return Police.distanceBetween(robberSrc, targetSrc) <= limit
end

---Whether `robberSrc` currently holds a valid rob grant on `targetSrc`.
---Consulted by the kora_inventory inspection policy in server/seize.lua.
---@param robberSrc integer
---@param targetSrc integer
---@return boolean
function Police.hasRobAccess(robberSrc, targetSrc)
    local grant = Police.robGrants[robberSrc]
    if not grant or grant.target ~= targetSrc then return false end
    if GetGameTimer() > grant.expires then return false end
    return robStillValid(robberSrc, targetSrc)
end

local function revokeRobGrant(robberSrc, closeInventory)
    local grant = Police.robGrants[robberSrc]
    if not grant then return end
    Police.robGrants[robberSrc] = nil
    if closeInventory and grant.opened then
        pcall(function() exports.kora_inventory:CloseInventory(robberSrc) end)
    end
end

---@param robberSrc integer
---@param targetSrc integer
---@return boolean, string|nil, number|nil amount cash taken (0 when only the inventory was opened)
function Police.rob(robberSrc, targetSrc)
    local cfg = robConfig()
    local takeCash, openInventory = cfg.takeCash ~= false, cfg.openInventory ~= false
    if not takeCash and not openInventory then return false, 'robbing is disabled' end
    if robberSrc == targetSrc then return false, 'cannot rob yourself' end
    if not exports.kora_core:getPlayerData(targetSrc) then return false, 'target not found' end
    if Police.distanceBetween(robberSrc, targetSrc) > Config.cuff.distance then return false, 'too far away' end
    if not Police.isIncapacitated(targetSrc) then return false, 'target is not restrained or down' end

    local amount = 0
    if takeCash then
        local available = exports.kora_core:getMoney(targetSrc, 'cash') or 0
        amount = math.min(available, MAX_ROB_AMOUNT)
        if amount <= 0 and not openInventory then return false, 'target has no cash' end
        if amount > 0 then
            local transferred, transferErr = exports.kora_core:transferMoney(targetSrc, robberSrc, 'cash', amount, 'robbery')
            if not transferred then
                if not openInventory then return false, transferErr or 'could not take cash' end
                amount = 0
            end
        end
    end

    if openInventory then
        local previous = Police.robGrants[robberSrc]
        Police.robGrants[robberSrc] = {
            target = targetSrc,
            expires = GetGameTimer() + (tonumber(cfg.accessSeconds) or 120) * 1000,
            opened = previous ~= nil and previous.target == targetSrc and previous.opened or false,
        }
        TriggerClientEvent('qbpolice:client:openRob', robberSrc, targetSrc)
    end
    return true, nil, amount
end

RegisterNetEvent('qbpolice:server:rob', function(target)
    local src = source
    local ok, err, amount = Police.rob(src, tonumber(target))
    if not ok then
        TriggerClientEvent('QBCore:Notify', src, err, 'error')
    elseif amount > 0 then
        TriggerClientEvent('QBCore:Notify', src, ('You took $%d.'):format(amount), 'success')
    else
        TriggerClientEvent('QBCore:Notify', src, 'You search them.', 'success')
    end
end)

-- Track whether the grant has an open player-inventory session so the sweep
-- only closes an inventory the rob opened. A 'replaced' close is the open
-- request itself (kora_inventory closes the previous session first).
AddEventHandler('qbinventory:server:sessionOpened', function(src, payload)
    local grant = Police.robGrants[src]
    if not grant then return end
    local secondary = type(payload) == 'table' and payload.secondary or nil
    grant.opened = type(secondary) == 'table' and secondary.type == 'player'
end)
AddEventHandler('qbinventory:server:sessionClosed', function(src, _, reason)
    if reason ~= 'replaced' then Police.robGrants[src] = nil end
end)

AddEventHandler('playerDropped', function()
    Police.robGrants[source] = nil
end)

function Police.sweepRobGrants()
    for robber, grant in pairs(Police.robGrants) do
        if GetGameTimer() > grant.expires or not robStillValid(robber, grant.target) then
            revokeRobGrant(robber, true)
        end
    end
end

CreateThread(function()
    while true do
        Wait(math.max(250, tonumber(robConfig().checkInterval) or 1000))
        Police.sweepRobGrants()
    end
end)
