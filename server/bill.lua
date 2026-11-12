-- Citations/fines and the `moneybag` useable item (cash payout).
--
-- An issued citation is stored in the recipient's `citations` metadata until
-- they pay it (see Config.Citations). With Config.Citations.autoDeduct the fine
-- is instead taken from Config.fine.account at once and nothing is stored.

local MAX_FINE = 100000

---@param targetSrc integer
---@return table[]
local function readCitations(targetSrc)
    local list = exports.kora_core:getMetaData(targetSrc, 'citations')
    return type(list) == 'table' and list or {}
end

---Unpaid citations of a player, oldest first.
---@param src integer
---@return table[]
function Police.getCitations(src)
    local out = {}
    for _, citation in ipairs(readCitations(src)) do out[#out + 1] = citation end
    return out
end

---@param officerSrc integer
---@param targetSrc integer
---@param amount number
---@param reason string|nil
---@return boolean, string|nil
function Police.bill(officerSrc, targetSrc, amount, reason)
    if not Police.isPolice(officerSrc) then return false, Kora.lang('Notify.on_duty_police') end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount <= 0 or amount > MAX_FINE then return false, Kora.lang('Notify.invalid_fine_amount') end
    if not targetSrc or not exports.kora_core:getPlayerData(targetSrc) then return false, Kora.lang('Notify.player_not_found') end
    if Police.distanceBetween(officerSrc, targetSrc) > Config.cuff.distance then return false, Kora.lang('Notify.too_far_away') end
    if type(reason) ~= 'string' or reason == '' then reason = nil end
    if reason then reason = reason:sub(1, 120) end

    local cfg = Config.Citations or {}
    if cfg.autoDeduct == true then
        local removed, err = exports.kora_core:removeMoney(targetSrc, Config.fine.account, amount, reason or 'citation')
        if not removed then
            -- Config.money.allowNegative decides whether this ever actually fails;
            -- surface the underlying reason (e.g. account floor) either way.
            return false, err or 'target could not pay the fine'
        end
        Police.notify(targetSrc, ('You were fined $%d%s.'):format(amount, reason and (' for ' .. reason) or ''), 'error')
        Police.notify(officerSrc, ('Citation of $%d charged to the player.'):format(amount), 'success')
        return true
    end

    local list = readCitations(targetSrc)
    local nextId = 1
    for _, citation in ipairs(list) do nextId = math.max(nextId, (tonumber(citation.id) or 0) + 1) end
    local officerName = exports.kora_core:getPlayerData(officerSrc, { 'charinfo', 'lastname' })
    list[#list + 1] = {
        id = nextId,
        amount = amount,
        reason = reason,
        officer = type(officerName) == 'string' and officerName or nil,
        issuedAt = os.time(),
    }
    while #list > (tonumber(cfg.maxUnpaid) or 25) do table.remove(list, 1) end
    local saved, saveErr = exports.kora_core:setMetaData(targetSrc, 'citations', list)
    if saved == false then return false, saveErr or 'could not store the citation' end

    local how = ''
    if cfg.payMethods and cfg.payMethods.command ~= false and cfg.payCommand and cfg.payCommand ~= '' then
        how = (' Type /%s %d to pay it (/%s lists them).'):format(cfg.payCommand, nextId, cfg.listCommand or 'citations')
    end
    Police.notify(targetSrc, ('You received citation #%d: $%d%s.%s'):format(
        nextId, amount, reason and (' for ' .. reason) or '', how), 'error')
    Police.notify(officerSrc, ('Citation #%d of $%d issued.'):format(nextId, amount), 'success')
    return true
end

---Pays one unpaid citation (the oldest when `id` is nil) from Config.fine.account.
---@param src integer
---@param id integer|nil
---@return boolean, string|nil
function Police.payCitation(src, id)
    local list = readCitations(src)
    if #list == 0 then return false, Kora.lang('Notify.you_have_no_unpaid_citations') end
    local index
    if id == nil then
        index = 1
    else
        for i, citation in ipairs(list) do
            if tonumber(citation.id) == tonumber(id) then index = i; break end
        end
    end
    if not index then return false, Kora.lang('Notify.no_unpaid_citation_with_that_number') end

    local citation = list[index]
    local removed, err = exports.kora_core:removeMoney(src, Config.fine.account, citation.amount, 'citation-payment')
    if not removed then return false, err or 'You cannot afford that citation.' end
    table.remove(list, index)
    exports.kora_core:setMetaData(src, 'citations', list)
    Police.notify(src, ('You paid citation #%d ($%d).'):format(citation.id, citation.amount), 'success')
    return true
end

RegisterNetEvent('kora_police:server:bill', function(target, amount, reason)
    local src = source -- only valid until the handler first yields
    local ok, err = Police.bill(src, tonumber(target), amount, reason)
    if not ok then Police.notify(src, Police.cuffRefusal(err)) end
end)

local cfg = Config.Citations or {}
local methods = cfg.payMethods or {}
if methods.command ~= false then
    Kora.commands.add(cfg.listCommand or 'citations', 'List your unpaid citations', {}, false, function(source)
        local list = Police.getCitations(source)
        if #list == 0 then return Police.notify(source, 'You have no unpaid citations.', 'inform') end
        for _, citation in ipairs(list) do
            Police.notify(source, ('#%d: $%d%s'):format(citation.id, citation.amount,
                citation.reason and (' - ' .. citation.reason) or ''), 'inform')
        end
        Police.notify(source, ('Pay with /%s [number].'):format(cfg.payCommand or 'paycitation'), 'inform')
    end)
    Kora.commands.add(cfg.payCommand or 'paycitation', 'Pay an unpaid citation', {
        { name = 'number', help = 'Citation number (default: oldest)' },
    }, false, function(source, args)
        local ok, err = Police.payCitation(source, tonumber(args and args[1]))
        if not ok then Police.notify(source, err) end
    end)
end

if methods.exports ~= false then
    exports('getCitations', function(src) return Police.getCitations(src) end)
    exports('payCitation', function(src, id) return Police.payCitation(src, tonumber(id)) end)
end

exports.kora_core:createUseable('moneybag', function(src, item)
    local amount = tonumber(item and item.info and item.info.amount) or 0
    local slot = tonumber(item and item.slot)
    if amount ~= math.floor(amount) or amount <= 0 or not slot then return false end
    local removed, removeErr = exports.kora_core:removeItem(src, 'moneybag', 1, slot, 'moneybag-payout')
    if not removed then return false, removeErr end
    local paid, payErr = exports.kora_core:addMoney(src, 'cash', amount, 'moneybag-payout')
    if not paid then
        exports.kora_core:addItem(src, 'moneybag', 1, slot, item.info or {}, 'moneybag-payout-rollback')
        return false, payErr
    end
    Police.notify(src, ('You deposited $%d in cash.'):format(amount), 'success')
    return true
end)
