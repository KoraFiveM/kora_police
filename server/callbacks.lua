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

-- Stock qb-policejob answers this for ANY caller: the on-duty LEO roster as
-- { source, label = callsign, job }. Kora keeps that shape open, but the richer
-- identity fields (citizenid, name, grade) are only added for police callers.
Kora.callback.register('police:GetDutyPlayers', function(src)
    local callerIsPolice = Police.isPolice(src)
    local out = {}
    for _, s in ipairs(exports.kora_core:getPlayersByJobType(Config.police.jobType, true)) do
        local data = exports.kora_core:getPlayerData(s)
        local entry = {
            source = s,
            label = data and data.metadata and data.metadata.callsign,
            job = (Police.job(s) or {}).name,
        }
        if callerIsPolice then
            entry.citizenid = data and data.citizenid
            entry.name = data and data.charinfo and (data.charinfo.firstname .. ' ' .. data.charinfo.lastname)
            entry.grade = Police.gradeLevel(s)
        end
        out[#out + 1] = entry
    end
    return out
end)

-- Stock shape: the NUMBER of on-duty LEO officers, to any caller (heist and
-- robbery scripts gate on it). Counts by job type, same as the cop-count broadcast.
Kora.callback.register('police:GetCops', function()
    return exports.kora_core:getDutyCountByType(Config.police.jobType) or 0
end)

-- Kora's own list form of the old `police:GetCops`: the on-duty officer sources
-- of the police job, for police callers only.
Kora.callback.register('qbpolice:server:getCops', function(src)
    if not Police.isPolice(src) then return {} end
    return dutySrcList()
end)

---Non-police callers may only ask about themselves or someone within reach,
---which is all the stock robbery flow needs; officers may ask about anyone.
local function isPlayerDead(src, target)
    target = tonumber(target) or src
    if target ~= src and not Police.isPolice(src)
        and Police.distanceBetween(src, target) > Config.cuff.distance then return false end
    if Police.isDowned(target) then return true end
    if exports.kora_core:getMetaData(target, 'isdead') ~= nil then return false end
    local ped = GetPlayerPed(target)
    if not ped or ped == 0 then return false end
    return GetEntityHealth(ped) <= 0
end
Kora.callback.register('police:isPlayerDead', isPlayerDead)
Kora.callback.register('police:server:isPlayerDead', isPlayerDead)

---Stock sends a WEAPON (hash or name) and asks about the caller's own gun; the
---older kora form sent a target player id. A number above 65535, a negative one
---or a string is a weapon; anything else is a target.
---@param src integer
---@param arg any
---@return boolean
local function isSilencedWeapon(src, arg)
    local target, wanted = src, nil
    if type(arg) == 'string' then
        wanted = joaat(arg) % 4294967296
    elseif type(arg) == 'number' then
        if arg > 65535 or arg < 0 then wanted = arg % 4294967296 else target = arg end
    end
    if target ~= src and not Police.isPolice(src) then return false end
    local ped = GetPlayerPed(target)
    if not ped or ped == 0 then return false end
    local weapon = GetSelectedPedWeapon(ped)
    local equipped = exports.kora_inventory:GetEquippedWeapon(target)
    if not equipped or type(equipped.name) ~= 'string' then return false end
    local equippedHash = joaat(equipped.name) % 4294967296
    -- The inventory is authoritative on what is held: it must be the selected
    -- weapon, and (stock form) the weapon the caller asked about.
    if equippedHash ~= weapon % 4294967296 then return false end
    if wanted and wanted ~= equippedHash then return false end
    for _, component in ipairs(equipped.components or {}) do
        local hash = type(component) == 'string' and joaat(component) or component
        if type(hash) == 'number' and SUPPRESSOR_COMPONENTS[hash % 4294967296] then return true end
    end
    return false
end
Kora.callback.register('police:IsSilencedWeapon', isSilencedWeapon)

Kora.callback.register('police:IsPoliceForcePresent', function(src, coords, radius)
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

-- Stock `police:server:IsPoliceForcePresent`: no arguments, true when a
-- senior LEO (grade level 2+) is around, for any caller. Stock does not look at
-- duty; kora requires on-duty so an off-duty chief does not suppress heists.
Kora.callback.register('police:server:IsPoliceForcePresent', function()
    for _, officer in ipairs(exports.kora_core:getPlayersByJobType(Config.police.jobType, true)) do
        local job = Police.job(officer)
        if job and (tonumber(job.grade and job.grade.level) or 0) >= 2 then return true end
    end
    return false
end)

-- Stock shape: the list of status texts a player reported (drunk, gunpowder, ...).
-- Stock answers anyone about anyone; here only an on-duty officer within reach.
Kora.callback.register('police:GetPlayerStatus', function(src, target)
    if not Police.isPolice(src) then return {} end
    target = tonumber(target) or src
    if target ~= src and Police.distanceBetween(src, target) > Config.evidence.statusDistance then return {} end
    return Police.getPlayerStatusList(target)
end)

-- Kora's own richer record, kept under a native name for kora callers.
Kora.callback.register('qbpolice:server:getPlayerStatus', function(src, target)
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
        status = Police.getPlayerStatusList(target),
    }
end)

Kora.callback.register('police:GetImpoundedVehicles', function(src)
    if not Police.isPolice(src) then return {} end
    return Police.getImpoundedVehicles()
end)

Kora.callback.register('police:IsPlateFlagged', function(src, plate)
    if not Police.isPolice(src) then return false end
    return Police.isPlateFlagged(plate)
end)

Kora.callback.register('police:server:IsPlateFlagged', function(src, plate)
    if not Police.isPolice(src) then return false end
    return Police.isPlateFlagged(plate)
end)
