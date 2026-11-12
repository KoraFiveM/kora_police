-- Evidence locker UI wiring -- opens the kora_inventory stash registered in
-- server/evidence.lua. No inventory logic lives here at all.

local function registerEvidenceLockerTargets()
    Police.target.reset('evidenceLocker')
    Police.target.box('evidenceLocker', {
        coords = Config.evidence.lockerCoords,
        size = { x = 1.5, y = 1.5, z = 2.0 },
        heading = Config.evidence.lockerCoords.w,
        distance = Config.evidence.lockerDistance,
        options = {
            {
                label = Config.evidence.lockerLabel,
                icon = 'archive',
                canInteract = function()
                    return Police.isOnDuty()
                end,
                onSelect = function()
                    exports.kora_inventory:openInventory('stash', Config.evidence.lockerStashId)
                end,
            },
        },
    })
end
registerEvidenceLockerTargets()

-- World evidence markers (blood/casing/fingerprint) -- compat rendering for
-- the legacy evidence:server:Create* events; deliberately simple blips, not
-- a new CSI minigame.

local markers = {}

local function removeWorldEvidence(id)
    local marker = markers[id]
    if not marker then return end
    if marker.blip then Kora.blips.remove(marker.blip) end
    if marker.zone then exports.kora_target:removeZone(marker.zone) end
    markers[id] = nil
end

local function registerWorldEvidenceTarget(id, marker)
    if marker.zone or marker.displayOnly or GetResourceState('kora_target') ~= 'started' then return end
    marker.zone = exports.kora_target:addSphereZone({
        coords = marker.coords,
        radius = 1.0,
        distance = 2.0,
        options = {
            {
                label = ('Collect %s evidence'):format(marker.type),
                icon = 'search',
                canInteract = function() return Police.isOnDuty() end,
                onSelect = function()
                    TriggerServerEvent('evidence:server:AddToInventory', id)
                end,
            },
        },
    })
end

local function showWorldEvidence(id, evType, coords, displayOnly)
    removeWorldEvidence(id)
    local sprite = evType == 'blood' and 616 or (evType == 'casing' and 141 or 499)
    local blip = Kora.blips.create(coords, {
        sprite = sprite,
        color = 1,
        scale = 0.7,
        category = 'Evidence',
        name = evType,
        info = {
            title = 'Evidence marker',
            rows = {
                { kind = 'name', label = 'Type', value = evType },
                { kind = 'wrappedText', value = 'On-duty officers can collect this evidence at the scene.' },
            },
        },
    })
    local marker = { blip = blip, type = evType, coords = coords, displayOnly = displayOnly }
    markers[id] = marker
    registerWorldEvidenceTarget(id, marker)
end

RegisterNetEvent('kora_police:client:worldEvidenceCreated', function(id, evType, coords)
    showWorldEvidence(id, evType, coords)
end)

-- Stock server broadcasts. Kora's server never sends them; a third-party script
-- that does gets a map blip only, under a separate id space, with no collect
-- target (collecting is authorised by the server's own marker registry).
local function externalMarker(evType, idIndex, coordsIndex)
    return function(...)
        local args = { ... }
        local id, coords = args[idIndex], args[coordsIndex]
        if id == nil or type(coords) ~= 'table' or not Police.isOnDuty() then return end
        showWorldEvidence('ext:' .. tostring(id), evType, coords, true)
    end
end
RegisterNetEvent('evidence:client:AddBlooddrop', externalMarker('blood', 1, 4))
RegisterNetEvent('evidence:client:AddFingerPrint', externalMarker('fingerprint', 1, 3))
RegisterNetEvent('evidence:client:AddCasing', externalMarker('casing', 1, 3))

local function removeExternal(id)
    removeWorldEvidence('ext:' .. tostring(id))
end
RegisterNetEvent('evidence:client:RemoveBlooddrop', removeExternal)
RegisterNetEvent('evidence:client:RemoveFingerprint', removeExternal)
RegisterNetEvent('evidence:client:RemoveCasing', removeExternal)

local function clearArea(evType, serverEvent, label)
    if not Police.isOnDuty() then return end
    local completed = Kora.progressbar.start({
        label = label,
        duration = 5000,
        canCancel = true,
        disable = { combat = true },
    })
    if not completed then return Police.notify('Cancelled.', 'error') end
    local position = GetEntityCoords(PlayerPedId())
    local list = {}
    for id, marker in pairs(markers) do
        if type(id) == 'number' and marker.type == evType
            and #(position - vector3(marker.coords.x, marker.coords.y, marker.coords.z)) < Config.evidence.clearDistance then
            list[#list + 1] = id
        end
    end
    TriggerServerEvent(serverEvent, list)
end
RegisterNetEvent('evidence:client:ClearBlooddropsInArea', function()
    clearArea('blood', 'evidence:server:ClearBlooddrops', 'Cleaning up blood...')
end)
RegisterNetEvent('evidence:client:ClearCasingsInArea', function()
    clearArea('casing', 'evidence:server:ClearCasings', 'Picking up casings...')
end)

-- Impairment signs other resources report on the local player (consumables, fights);
-- the server keeps only the ids it recognises, with its own labels.
local statuses = {}
local ticking = false
local function startStatusTick()
    if ticking then return end
    ticking = true
    CreateThread(function()
        while next(statuses) do
            Wait(10000)
            for id, status in pairs(statuses) do
                status.time = status.time - 10
                if status.time <= 0 then statuses[id] = nil end
            end
            TriggerServerEvent('evidence:server:UpdateStatus', statuses)
        end
        ticking = false
    end)
end
RegisterNetEvent('evidence:client:SetStatus', function(statusId, time)
    local label = type(statusId) == 'string' and Config.evidence.statuses[statusId]
    if not label then return end
    time = tonumber(time) or 0
    if time > 0 then
        if not statuses[statusId] or statuses[statusId].time < 20 then
            statuses[statusId] = { text = label, time = time }
            Police.notify(label, 'error')
        end
    else
        statuses[statusId] = nil
    end
    TriggerServerEvent('evidence:server:UpdateStatus', statuses)
    startStatusTick()
end)


RegisterNetEvent('kora_police:client:worldEvidenceRemoved', removeWorldEvidence)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= 'kora_target' then return end
    -- Stopped providers discard zones and may reuse their IDs on restart.
    for _, marker in pairs(markers) do marker.zone = nil end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= 'kora_target' then return end
    registerEvidenceLockerTargets()
    for id, marker in pairs(markers) do registerWorldEvidenceTarget(id, marker) end
end)
