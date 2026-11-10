-- Fresh armory build via kora_inventory's existing shop primitive
-- (`exports.kora_inventory:RegisterShop`) -- neither qb-policejob nor qbx_police
-- ships a maintained armory (qb-policejob's Config.ArmoryWhitelist is an
-- empty stub; qbx_police punts to ox_inventory shops entirely), so this is
-- genuine new work, not a port.
--
-- Grade-gating choice: rather than a per-item price gate, each armory ROOM is
-- its own shop registered with a `minGrade`, and access to open that shop at
-- all is checked server-side against the requesting officer's
-- `job.grade.level` before the shop's kora_target zone will even let the client
-- try to open it (see client/duty.lua's armory zones). `price = 0` items are
-- the patrol-tier free-issue kit; anything above 0 is a chargeable upgrade
-- even for an officer who qualifies for that room.

Police.armoryShops = Police.armoryShops or {}

---kora_inventory keeps a shop's stock across restarts and never reseeds a
---restored one, so an armory saved before an item was added to its config
---would never show that item, and free-issue kit that ran out stayed out.
---With Config.armory.restockOnStart, when this resource starts, every
---configured row missing from the saved stock is put back and every row below
---its configured amount is topped up; rows that hold another item (a reordered
---config) are left alone. A kora_inventory restart mid-session does not
---restock: what was taken this session stays taken.
---@param shop table A Config.armory.shops entry.
---@return boolean changed
function Police.restockArmory(shop)
    if Config.armory.restockOnStart == false then return false end
    local current = exports.kora_inventory:GetShopItems(shop.id)
    if type(current) ~= 'table' then return false end
    local changed = false
    for index, row in ipairs(shop.items or {}) do
        local slot = math.floor(tonumber(row.slot) or index)
        local stocked = current[slot]
        if not stocked then
            current[slot] = { name = row.name, amount = row.amount, price = row.price }
            changed = true
        elseif stocked.name == row.name and (tonumber(stocked.amount) or 0) < row.amount then
            stocked.amount = row.amount
            changed = true
        end
    end
    if not changed then return false end
    local ok, err = exports.kora_inventory:SetShopItems(shop.id, current)
    if not ok then
        print(('^3[kora_police] armory %s could not be restocked: %s^7'):format(shop.id, tostring(err)))
        return false
    end
    return true
end

-- Registers every armory-room shop against kora_inventory. Called once at load
-- (via the dependency-ordering guarantee below) AND again on every
-- kora_inventory onResourceStart -- a `dependency 'kora_inventory'` declaration
-- only guarantees START ORDER on a fresh boot, not survival of a later
-- kora_inventory RESTART mid-session, which wipes kora_inventory's own shop table
-- without touching kora_police at all.
local function registerArmoryShops()
    for _, shop in ipairs(Config.armory.shops) do
        -- `groups` is kora_inventory's own job/grade access check (see its
        -- server.lua canAccess/groupAllowed) -- set here so the shop is
        -- refused by kora_inventory itself for a non-qualifying officer even if
        -- something bypasses this resource's own openArmory gate below.
        local key = exports.kora_inventory:RegisterShop(shop.id, {
            slots = shop.slots,
            inventory = shop.items,
            currency = 'money',
            groups = { [Config.police.job] = shop.minGrade },
            coords = shop.coords,
            distance = shop.distance,
            access = function(src) return Police.canAccessArmory(src, shop.id) end,
        })
        Police.armoryShops[shop.id] = { config = shop, key = key }
    end
end

-- Config.armory.restockOnStart runs once per start of this resource. On a
-- server boot kora_inventory loads its saved shops from the database only
-- after this resource has registered them, and that load replaces the
-- registered stock with the saved one, so restocking at registration was
-- undone straight away. The restock therefore waits for kora_inventory's
-- 'kora_inventory:server:ready' (saved inventories loaded) unless it has
-- already loaded them.
local restockPending = Config.armory.restockOnStart ~= false

---@return boolean waiting kora_inventory has not loaded its saved shops yet.
local function awaitingInventoryLoad()
    local ok, status = pcall(function() return exports.kora_inventory:getPersistenceStatus() end)
    if not ok or type(status) ~= 'table' then return false end
    return status.enabled == true and status.ready ~= true and not status.lastError
end

local function restockArmories()
    restockPending = false
    for _, shop in ipairs(Config.armory.shops) do
        local registered = Police.armoryShops[shop.id]
        if registered and registered.key then Police.restockArmory(shop) end
    end
end

CreateThread(function()
    registerArmoryShops()
    if restockPending and not awaitingInventoryLoad() then restockArmories() end
end)

AddEventHandler('kora_inventory:server:ready', function()
    -- Only the load that follows this resource starting: a later
    -- kora_inventory restart keeps what was taken this session.
    if not restockPending or not next(Police.armoryShops) then return end
    CreateThread(restockArmories)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'kora_inventory' then CreateThread(registerArmoryShops) end
end)

---@param src integer
---@param shopId string
---@return boolean, string|nil
function Police.canAccessArmory(src, shopId)
    if not Police.isPolice(src) then return false, 'not an on-duty officer' end
    local shop = Police.armoryShops[shopId]
    if not shop then return false, 'unknown armory' end
    if Police.gradeLevel(src) < shop.config.minGrade then return false, 'insufficient rank' end

    local ped = GetPlayerPed(src)
    local coords = shop.config.coords
    if ped and ped ~= 0 and coords then
        local dist = #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z))
        if dist > (shop.config.distance or 2.0) then return false, 'too far away' end
    end
    return true
end

RegisterNetEvent('kora_police:server:openArmory', function(shopId)
    local src = source
    local ok, err = Police.canAccessArmory(src, shopId)
    if not ok then TriggerClientEvent('QBCore:Notify', src, err, 'error'); return end
    TriggerClientEvent('kora_police:client:openArmory', src, shopId)
end)

Kora.callback.register('kora_police:server:canAccessArmory', function(src, shopId)
    return Police.canAccessArmory(src, shopId)
end)
