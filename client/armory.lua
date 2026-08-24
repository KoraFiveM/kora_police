-- Armory rooms. The grade gate is enforced server-side twice (this
-- resource's own openArmory check, and qbinventory's own shop `groups`
-- policy) -- canInteract here is purely a UX convenience so a
-- non-qualifying officer doesn't even see the option.

RegisterNetEvent('qbpolice:client:openArmory', function(shopId)
    exports.qbinventory:openInventory('shop', shopId)
end)

local function registerArmoryTargets()
    for _, shop in ipairs(Config.armory.shops) do
        exports.qbtarget:addBoxZone({
            coords = shop.coords,
            size = { x = 1.5, y = 1.5, z = 2.0 },
            heading = shop.coords.w,
            distance = shop.distance,
            options = {
                {
                    label = shop.label,
                    icon = 'shield',
                    canInteract = function()
                        return Police.isOnDuty() and Police.myGradeLevel() >= shop.minGrade
                    end,
                    onSelect = function()
                        TriggerServerEvent('qbpolice:server:openArmory', shop.id)
                    end,
                },
            },
        })
    end
end
registerArmoryTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qbtarget' then registerArmoryTargets() end
end)
