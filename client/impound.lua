-- Officer impounds a nearby vehicle; any player can retrieve one from an
-- impound lot for the fee. Both wired straight onto Core.garage via
-- server/impound.lua -- no vehicle persistence lives here.

exports.qbtarget:addGlobalType('vehicle', {
    options = {
        {
            label = 'Impound Vehicle',
            icon = 'lock',
            canInteract = function()
                return Police.isOnDuty()
            end,
            onSelect = function(entity)
                local plate = GetVehicleNumberPlateText(entity)
                TriggerServerEvent('qbpolice:server:impound', plate)
                if DoesEntityExist(entity) then DeleteEntity(entity) end
            end,
        },
    },
})

for _, lot in ipairs(Config.impound.lots) do
    exports.qbtarget:addSphereZone({
        coords = lot.coords,
        radius = 2.0,
        distance = 3.0,
        options = {
            {
                label = ('Retrieve From %s ($%d)'):format(lot.label, Config.impound.fee),
                icon = 'car',
                onSelect = function()
                    local result = QB.nui.openInputDialog(
                        { { id = 'plate', label = 'Plate', type = 'text', required = true } },
                        'Retrieve Vehicle'
                    )
                    if result and result.values and result.values.plate then
                        TriggerServerEvent('qbpolice:server:retrieveImpound', result.values.plate)
                    end
                end,
            },
        },
    })
end
