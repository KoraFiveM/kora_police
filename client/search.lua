-- Search a restrained suspect. The server validates and then tells the
-- OFFICER's own client to open the target's inventory (qbinventory's
-- `openInventory` export lives in the client realm -- see server/seize.lua
-- for why the round trip goes through this event instead of a direct call).

RegisterNetEvent('qbpolice:client:openSearch', function(targetServerId)
    exports.qbinventory:openInventory('player', targetServerId)
end)

local function registerSearchTargets()
    Police.target.reset('search')
    Police.target.global('search', 'player', {
        {
            label = 'Search',
            icon = 'search',
            canInteract = function(entity)
                return Police.isOnDuty() and IsPedCuffed(entity)
            end,
            onSelect = function(entity)
                TriggerServerEvent('qbpolice:server:search', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
        },
    }, Config.cuff.distance)
end
registerSearchTargets()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qbtarget' then registerSearchTargets() end
end)
