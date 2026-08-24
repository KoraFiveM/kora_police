-- Remaining `police:client:*` legacy listeners not naturally owned by a more
-- specific file. Most of the checklist's other legacy names are handled
-- directly where the matching feature lives (cuff.lua, escort.lua,
-- search.lua, dispatch.lua, tracker.lua, fingerprint.lua, plate_flag.lua,
-- spikes.lua) so third-party scripts see event-name parity without a second
-- forwarding hop.

RegisterNetEvent('police:client:SearchPlayer', function(targetServerId)
    exports.qbinventory:openInventory('player', targetServerId)
end)

RegisterNetEvent('police:client:SyncSpikes', function(netId, active)
    if active == false then TriggerEvent('qbpolice:client:spikeRemoved', tonumber(netId)) end
end)
RegisterNetEvent('police:client:spawnObject', function(netId, coords)
    TriggerEvent('qbpolice:client:spikeDeployed', tonumber(netId), coords)
end)

-- `GetEscorted`/`GetKidnappedTarget`/`GetKidnappedDragger` are server
-- callbacks (see server/compat/police.lua); no client-side mirror is needed
-- since Police.escortedTarget/draggedTarget already track this resource's
-- own local state.
