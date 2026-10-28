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
    if marker.blip then QB.blips.remove(marker.blip) end
    if marker.zone then exports.kora_target:removeZone(marker.zone) end
    markers[id] = nil
end

local function registerWorldEvidenceTarget(id, marker)
    if marker.zone or GetResourceState('kora_target') ~= 'started' then return end
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

RegisterNetEvent('qbpolice:client:worldEvidenceCreated', function(id, evType, coords)
    removeWorldEvidence(id)
    local sprite = evType == 'blood' and 616 or (evType == 'casing' and 141 or 499)
    local blip = QB.blips.create(coords, {
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
    local marker = { blip = blip, type = evType, coords = coords }
    markers[id] = marker
    registerWorldEvidenceTarget(id, marker)
end)

RegisterNetEvent('qbpolice:client:worldEvidenceRemoved', removeWorldEvidence)

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
