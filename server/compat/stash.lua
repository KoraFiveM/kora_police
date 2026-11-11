-- Stock `qb-policejob:server:stash` / `trash` / `evidence`. Each opens a
-- kora_inventory stash for an on-duty officer only. Stash ids keep the stock
-- names (`policestash_<citizenid>`, `policetrash`, `<room> | Drawer <n>`) so
-- contents migrated from qb-inventory line up. The evidence request carries a
-- client-chosen id, so it is parsed against the configured rooms and drawers
-- and never passed through as-is.

local function nearAny(src, points, distance)
    if not points or #points == 0 then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local position = GetEntityCoords(ped)
    for _, point in ipairs(points) do
        if #(position - vector3(point.x, point.y, point.z)) <= distance then return true end
    end
    return false
end

local function openStash(src, id, label, slots, maxWeight, owner, minGrade)
    exports.kora_inventory:RegisterStash(id, label, slots, maxWeight, owner, { [Config.police.job] = minGrade })
    return exports.kora_inventory:OpenInventory(src, id)
end

RegisterNetEvent('qb-policejob:server:stash', function()
    local src = source
    if not Police.isPolice(src) or not nearAny(src, Config.stash.locations, Config.stash.distance) then return end
    local cid = Police.citizenId(src)
    if not cid then return end
    openStash(src, 'policestash_' .. cid, 'Police Stash', Config.stash.personal.slots, Config.stash.personal.maxWeight, cid, 0)
end)

RegisterNetEvent('qb-policejob:server:trash', function()
    local src = source
    if not Police.isPolice(src) or not nearAny(src, Config.stash.locations, Config.stash.distance) then return end
    openStash(src, 'policetrash', 'Police Trash', Config.stash.trash.slots, Config.stash.trash.maxWeight, nil, 0)
end)

---@param requested any
---@return string|nil id, integer|nil room
local function parseDrawer(requested)
    if type(requested) ~= 'string' or #requested > 32 then return nil end
    local room, drawer = requested:match('^(%d+) | Drawer (%d+)$')
    room, drawer = tonumber(room), tonumber(drawer)
    local cfg = Config.evidence.drawers
    if not room or not drawer or not cfg.rooms[room] or drawer < 1 or drawer > cfg.maxDrawer then return nil end
    return ('%d | Drawer %d'):format(room, drawer), room
end

RegisterNetEvent('qb-policejob:server:evidence', function(requested)
    local src = source
    if not Police.isPolice(src) or Police.gradeLevel(src) < Config.evidence.minGradeToAccess then return end
    local id, room = parseDrawer(requested)
    if not id then return end
    local cfg = Config.evidence.drawers
    if not nearAny(src, { cfg.rooms[room] }, cfg.distance) then return end
    openStash(src, id, 'Evidence Stash | ' .. id, cfg.slots, cfg.maxWeight, nil, Config.evidence.minGradeToAccess)
end)

---@return boolean
function Police.clearTrash()
    local ok, result = pcall(function() return exports.kora_inventory:SetStashItems('policetrash', {}) end)
    return ok and result ~= false
end

if Config.stash.clearTrashOnStart then
    CreateThread(function()
        for _ = 1, 3 do
            if Police.clearTrash() then return end
            Wait(5000)
        end
    end)
end
