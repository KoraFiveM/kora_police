-- MDT-readiness surface. No UI (deferred per the plan) -- just the server
-- callbacks a future MDT resource can consume without any rework here.

local SUPPRESSOR_COMPONENTS = {}
for _, name in ipairs({
    'COMPONENT_AT_PI_SUPP', 'COMPONENT_AT_PI_SUPP_02', 'COMPONENT_AT_AR_SUPP',
    'COMPONENT_AT_AR_SUPP_02', 'COMPONENT_AT_SR_SUPP',
}) do
    SUPPRESSOR_COMPONENTS[joaat(name) % 4294967296] = true
end

---@return integer[]
local function dutySrcList()
    return exports.kora_core:getPlayersByJob(Config.police.job, true)
end

QB.callback.register('police:GetDutyPlayers', function(src)
    if not Police.isPolice(src) then return {} end
    local out = {}
    for _, s in ipairs(dutySrcList()) do
        local data = exports.kora_core:getPlayerData(s)
        out[#out + 1] = { source = s, citizenid = data and data.citizenid, name = data and data.charinfo and (data.charinfo.firstname .. ' ' .. data.charinfo.lastname), grade = Police.gradeLevel(s) }
    end
    return out
end)

QB.callback.register('police:GetCops', function(src)
    if not Police.isPolice(src) then return {} end
    return dutySrcList()
end)

QB.callback.register('police:isPlayerDead', function(src, target)
    target = target or src
    if target ~= src and not Police.isPolice(src) then return false end
    if Police.isDowned(target) then return true end
    if exports.kora_core:getMetaData(target, 'isdead') ~= nil then return false end
    local ped = GetPlayerPed(target)
    if not ped or ped == 0 then return false end
    return GetEntityHealth(ped) <= 0
end)

QB.callback.register('police:IsSilencedWeapon', function(src, target)
    target = target or src
    if target ~= src and not Police.isPolice(src) then return false end
    local ped = GetPlayerPed(target)
    if not ped or ped == 0 then return false end
    local weapon = GetSelectedPedWeapon(ped)
    local equipped = exports.kora_inventory:GetEquippedWeapon(target)
    if not equipped or type(equipped.name) ~= 'string'
        or joaat(equipped.name) % 4294967296 ~= weapon % 4294967296 then return false end
    for _, component in ipairs(equipped.components or {}) do
        local hash = type(component) == 'string' and joaat(component) or component
        if type(hash) == 'number' and SUPPRESSOR_COMPONENTS[hash % 4294967296] then return true end
    end
    return false
end)

QB.callback.register('police:IsPoliceForcePresent', function(src, coords, radius)
    if not Police.isPolice(src) then return false end
    coords = coords or (GetPlayerPed(src) ~= 0 and GetEntityCoords(GetPlayerPed(src)))
    if not coords then return false end
    radius = tonumber(radius) or Config.dispatch.robberyRadius
    for _, officer in ipairs(dutySrcList()) do
        local ped = GetPlayerPed(officer)
        if ped and ped ~= 0 and #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) <= radius then
            return true
        end
    end
    return false
end)

QB.callback.register('police:GetPlayerStatus', function(src, target)
    if not Police.isPolice(src) then return nil end
    target = tonumber(target) or src
    local data = exports.kora_core:getPlayerData(target)
    if not data then return nil end
    return {
        citizenid = data.citizenid,
        job = data.job,
        cuffed = Police.isCuffed(target),
        tracked = Police.tracked[target] == true,
        escortedBy = Police.escorted[target],
        draggedBy = Police.kidnapped[target],
    }
end)

QB.callback.register('police:GetImpoundedVehicles', function(src)
    if not Police.isPolice(src) then return {} end
    return Police.getImpoundedVehicles()
end)

QB.callback.register('police:IsPlateFlagged', function(src, plate)
    if not Police.isPolice(src) then return false end
    return Police.isPlateFlagged(plate)
end)
