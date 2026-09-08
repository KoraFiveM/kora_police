-- Evidence locker UI wiring -- opens the qbinventory stash registered in
-- server/evidence.lua. No inventory logic lives here at all.

local function registerEvidenceLockerTargets()
    exports.qbtarget:addBoxZone({
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
                    exports.qbinventory:openInventory('stash', Config.evidence.lockerStashId)
                end,
            },
        },
    })
end
registerEvidenceLockerTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qbtarget' then registerEvidenceLockerTargets() end
end)

-- World evidence markers (blood/casing/fingerprint) -- compat rendering for
-- the legacy evidence:server:Create* events; deliberately simple blips, not
-- a new CSI minigame.

local markers = {}

RegisterNetEvent('qbpolice:client:worldEvidenceCreated', function(id, evType, coords)
    local sprite = evType == 'blood' and 616 or (evType == 'casing' and 141 or 499)
    local blip = QB.blips.create(coords, {
        sprite = sprite,
        color = 1,
        scale = 0.7,
        label = ('Evidence: %s'):format(evType),
        info = {
            title = 'Evidence marker',
            rows = {
                { kind = 'name', label = 'Type', value = evType },
                { kind = 'wrappedText', value = 'On-duty officers can collect this evidence at the scene.' },
            },
        },
    })
    if blip then markers[id] = blip end

    exports.qbtarget:addSphereZone({
        coords = coords,
        radius = 1.0,
        distance = 2.0,
        options = {
            {
                label = ('Collect %s evidence'):format(evType),
                icon = 'search',
                canInteract = function() return Police.isOnDuty() end,
                onSelect = function()
                    TriggerServerEvent('evidence:server:AddToInventory', id)
                    Police.notify('Evidence collected.', 'success')
                    if markers[id] then QB.blips.remove(markers[id]); markers[id] = nil end
                end,
            },
        },
    })
end)
