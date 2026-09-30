-- Fresh armory build via qbinventory's existing shop primitive
-- (`exports.qbinventory:RegisterShop`) -- neither qb-policejob nor qbx_police
-- ships a maintained armory (qb-policejob's Config.ArmoryWhitelist is an
-- empty stub; qbx_police punts to ox_inventory shops entirely), so this is
-- genuine new work, not a port.
--
-- Grade-gating choice: rather than a per-item price gate, each armory ROOM is
-- its own shop registered with a `minGrade`, and access to open that shop at
-- all is checked server-side against the requesting officer's
-- `job.grade.level` before the shop's qbtarget zone will even let the client
-- try to open it (see client/duty.lua's armory zones). `price = 0` items are
-- the patrol-tier free-issue kit; anything above 0 is a chargeable upgrade
-- even for an officer who qualifies for that room.

Police.armoryShops = Police.armoryShops or {}

-- Registers every armory-room shop against qbinventory. Called once at load
-- (via the dependency-ordering guarantee below) AND again on every
-- qbinventory onResourceStart -- a `dependency 'qbinventory'` declaration
-- only guarantees START ORDER on a fresh boot, not survival of a later
-- qbinventory RESTART mid-session, which wipes qbinventory's own shop table
-- without touching qbpolice at all.
local function registerArmoryShops()
    for _, shop in ipairs(Config.armory.shops) do
        -- `groups` is qbinventory's own job/grade access check (see its
        -- server.lua canAccess/groupAllowed) -- set here so the shop is
        -- refused by qbinventory itself for a non-qualifying officer even if
        -- something bypasses this resource's own openArmory gate below.
        local key = exports.qbinventory:RegisterShop(shop.id, {
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

CreateThread(registerArmoryShops)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'qbinventory' then CreateThread(registerArmoryShops) end
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

RegisterNetEvent('qbpolice:server:openArmory', function(shopId)
    local src = source
    local ok, err = Police.canAccessArmory(src, shopId)
    if not ok then TriggerClientEvent('QBCore:Notify', src, err, 'error'); return end
    TriggerClientEvent('qbpolice:client:openArmory', src, shopId)
end)

QB.callback.register('qbpolice:server:canAccessArmory', function(src, shopId)
    return Police.canAccessArmory(src, shopId)
end)
