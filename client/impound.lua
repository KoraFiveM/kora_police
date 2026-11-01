-- Officer impounds a nearby vehicle; any player can retrieve one from an
-- impound lot for the fee. Both wired straight onto Core.garage via
-- server/impound.lua -- no vehicle persistence lives here.

local impounding = false

-- Impounds only once the progress bar completes (Config.impound.progress);
-- cancelling it (or moving the vehicle out of reach) leaves the car untouched.
local function impoundVehicle(entity)
    if impounding or not DoesEntityExist(entity) then return end
    local plate = GetVehicleNumberPlateText(entity)
    local progress = Config.impound.progress or {}
    if progress.enabled ~= false then
        impounding = true
        local props = progress.prop and { progress.prop } or nil
        local ok, completed = pcall(Kora.progressbar.start, {
            label = progress.label or 'Impounding vehicle...',
            duration = tonumber(progress.duration) or 5000,
            canCancel = progress.canCancel ~= false,
            anim = progress.anim,
            props = props,
            disable = { move = true, combat = true, car = true },
        })
        impounding = false
        if not ok then return Police.notify('Impound progress could not start: ' .. tostring(completed), 'error') end
        if not completed then return Police.notify('Impound cancelled.', 'warning') end
        if not DoesEntityExist(entity) then return end
    end
    TriggerServerEvent('qbpolice:server:impound', plate)
    if DoesEntityExist(entity) then DeleteEntity(entity) end
end

local function registerImpoundTargets()
    Police.target.reset('impound')
    Police.target.global('impound', 'vehicle', {
        {
            label = 'Impound Vehicle',
            icon = 'lock',
            canInteract = function()
                return Police.isOnDuty()
            end,
            onSelect = function(entity)
                impoundVehicle(entity)
            end,
        },
    })

    for _, lot in ipairs(Config.impound.lots) do
        Police.target.sphere('impound', {
            coords = lot.coords,
            radius = 2.0,
            distance = 3.0,
            options = {
                {
                    label = ('Retrieve From %s ($%d)'):format(lot.label, Config.impound.fee),
                    icon = 'car',
                    onSelect = function()
                        local result = Kora.nui.openInputDialog(
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
end
registerImpoundTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'kora_target' then registerImpoundTargets() end
end)
