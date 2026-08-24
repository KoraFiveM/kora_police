-- Search a restrained suspect. The server validates and then tells the
-- OFFICER's own client to open the target's inventory (qbinventory's
-- `openInventory` export lives in the client realm -- see server/seize.lua
-- for why the round trip goes through this event instead of a direct call).

RegisterNetEvent('qbpolice:client:openSearch', function(targetServerId)
    exports.qbinventory:openInventory('player', targetServerId)
end)

exports.qbtarget:addGlobalType('player', {
    options = {
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
    },
}, Config.cuff.distance)
