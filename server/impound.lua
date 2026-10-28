-- Civilian vehicle impound, entirely on Core.garage (exports.kora_core:impound/
-- retrieveImpound/getByPlate) -- no new persistence here. Core.garage has no
-- "list every impounded vehicle" query of its own, so this file keeps a
-- small in-memory index of the plates *this resource* has impounded, for the
-- MDT-readiness `GetImpoundedVehicles` callback (server/callbacks.lua).

Police.impoundedPlates = Police.impoundedPlates or {}  -- plate -> { lot, fee, impoundedAt, impoundedBy }

---@param officerSrc integer
---@param plate string
---@param lotId string|nil
---@return boolean, string|nil
function Police.impound(officerSrc, plate, lotId)
    if not Police.isPolice(officerSrc) then return false, 'not an on-duty officer' end
    if type(plate) ~= 'string' or plate == '' then return false, 'invalid plate' end
    local vehicle = Police.findVehicleByPlate(plate)
    if not vehicle or Police.distanceToEntity(officerSrc, vehicle) > Config.cuff.distance + 2.0 then
        return false, 'vehicle is not nearby'
    end
    local lot = lotId
    if not lot then
        local first = Config.impound.lots[1]
        lot = first and first.id or nil
    end

    local ok, err = exports.kora_core:impound(plate, Config.impound.fee, lot)
    if not ok then return false, err end
    DeleteEntity(vehicle)
    Police.impoundedPlates[plate] = { lot = lot, fee = Config.impound.fee, impoundedAt = os.time(), impoundedBy = officerSrc }
    return true
end

---@param src integer
---@param plate string
---@return boolean, string|nil
function Police.retrieveImpound(src, plate)
    local row = exports.kora_core:getByPlate(plate)
    if not row then return false, 'unknown vehicle' end
    if row.state ~= 'impounded' then return false, 'vehicle is not impounded' end

    local fee = tonumber(row.impound_fee) or Config.impound.fee
    if fee > 0 then
        local paid = exports.kora_core:removeMoney(src, 'cash', fee, 'impound-fee')
        if not paid then return false, 'cannot afford the impound fee' end
    end

    local ok, err = exports.kora_core:retrieveImpound(src, plate)
    if not ok then
        if fee > 0 then exports.kora_core:addMoney(src, 'cash', fee, 'impound-fee-refund') end
        return false, err
    end
    Police.impoundedPlates[plate] = nil
    return true
end

---@return table[] { plate, lot, fee, impoundedAt }
function Police.getImpoundedVehicles()
    local out = {}
    for plate, entry in pairs(Police.impoundedPlates) do
        local row = exports.kora_core:getByPlate(plate)
        if row and row.state == 'impounded' then
            out[#out + 1] = { plate = plate, lot = entry.lot, fee = entry.fee, impoundedAt = entry.impoundedAt, model = row.model }
        else
            Police.impoundedPlates[plate] = nil
        end
    end
    return out
end

RegisterNetEvent('qbpolice:server:impound', function(plate, lotId)
    local ok, err = Police.impound(source, plate, lotId)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
RegisterNetEvent('qbpolice:server:retrieveImpound', function(plate)
    local ok, err = Police.retrieveImpound(source, plate)
    if not ok then TriggerClientEvent('QBCore:Notify', source, err, 'error') end
end)
