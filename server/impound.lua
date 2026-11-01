-- Civilian vehicle impound, entirely on Core.garage (exports.kora_core:impound/
-- retrieveImpound/getByPlate) -- no new persistence here. Core.garage has no
-- "list every impounded vehicle" query of its own, so this file keeps a
-- small in-memory index of the plates *this resource* has impounded, for the
-- MDT-readiness `GetImpoundedVehicles` callback (server/callbacks.lua).

Police.impoundedPlates = Police.impoundedPlates or {}  -- plate -> { lot, fee, impoundedAt, impoundedBy }

---@param officerSrc integer
---@param plate string
---@param lotId string|nil
---@param opts table|nil { fee = number, full = boolean }
---@return boolean, string|nil
function Police.impound(officerSrc, plate, lotId, opts)
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

    local fee = opts and opts.fee or Config.impound.fee
    local ok, err = exports.kora_core:impound(plate, fee, lot)
    if not ok then return false, err end
    pcall(function()
        exports.kora_core:updateState(plate, { bodyHealth = GetVehicleBodyHealth(vehicle), engineHealth = GetVehicleEngineHealth(vehicle) })
    end)
    DeleteEntity(vehicle)
    Police.impoundedPlates[plate] = {
        lot = lot, fee = fee, impoundedAt = os.time(), impoundedBy = officerSrc, full = opts and opts.full == true or nil,
    }
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

---@return table[] { plate, lot, fee, impoundedAt, model, full } plus the stock row aliases `vehicle`, `depotprice`, `state`
function Police.getImpoundedVehicles()
    local out = {}
    for plate, entry in pairs(Police.impoundedPlates) do
        local row = exports.kora_core:getByPlate(plate)
        if row and row.state == 'impounded' then
            out[#out + 1] = {
                plate = plate, lot = entry.lot, fee = entry.fee, impoundedAt = entry.impoundedAt, model = row.model, full = entry.full,
                vehicle = row.model, depotprice = entry.fee, state = 2,
                engine = row.engine_health, body = row.body_health, fuel = row.fuel,
            }
        else
            Police.impoundedPlates[plate] = nil
        end
    end
    return out
end

---Stock `police:server:Impound(plate, fullImpound, price, body, engine, fuel)`.
---The client-reported body/engine/fuel are ignored (the vehicle is read
---server-side); `price` becomes the fee, capped by Config.impound.maxFee, and a
---full impound keeps the configured fee.
---@return boolean, string|nil
function Police.legacyImpound(src, plate, fullImpound, price)
    if type(plate) == 'string' then plate = (plate:gsub('^%s+', ''):gsub('%s+$', '')) end
    local fee
    if not fullImpound then
        price = tonumber(price)
        if price and price == price and price >= 0 then fee = math.min(math.floor(price), Config.impound.maxFee) end
    end
    return Police.impound(src, plate, nil, { fee = fee, full = fullImpound == true })
end

---Stock `police:server:TakeOutImpound(plate, garage)`: `garage` indexes the
---impound lots. Stock lets anyone clear any plate; here the caller must stand at
---that lot and be the owner (kora_core's retrieveImpound), paying the fee.
---@return boolean, string|nil
function Police.legacyTakeOutImpound(src, plate, garage)
    if type(plate) ~= 'string' or plate == '' or #plate > 16 then return false, 'invalid plate' end
    local lot = Config.impound.lots[tonumber(garage) or 1]
    if not lot then return false, 'unknown impound lot' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'no ped' end
    local position = GetEntityCoords(ped)
    if #(position - vector3(lot.coords.x, lot.coords.y, lot.coords.z)) > Config.impound.takeOutDistance then
        return false, 'too far from the impound lot'
    end
    return Police.retrieveImpound(src, plate)
end

RegisterNetEvent('qbpolice:server:impound', function(plate, lotId)
    local ok, err = Police.impound(source, plate, lotId)
    if not ok then Police.notify(source, err) end
end)
RegisterNetEvent('qbpolice:server:retrieveImpound', function(plate)
    local ok, err = Police.retrieveImpound(source, plate)
    if not ok then Police.notify(source, err) end
end)
