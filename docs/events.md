---
title: Events
sidebar_position: 9
---

# Events and callbacks

Native events use the `kora_police:` prefix. Legacy names are in [Legacy compatibility](./compatibility.md). All server events validate the caller; `source` is always the player who fired the event. Refusals are notified to the caller.

Three events go through `Kora.events` (fire them with `Kora.events.trigger`, client side): `kora_police:server:toggleDuty` (2 per 3 s), `kora_police:server:requestBackup` (2 per 5 s) and `kora_police:server:crimeDetected` (8 per 5 s). Everything else is a plain net event.

## Server events (client to server)

| Event | Arguments | Notes |
| --- | --- | --- |
| `kora_police:server:cuff` | `target` | On-duty officer, target in range |
| `kora_police:server:uncuff` | `target` | Officer, soft-cuffer or the cuffed player after a successful escape |
| `kora_police:server:breakCuffsResult` | `proof` or `false` | `proof` is the one-use `kora_lib` minigame proof; anything else counts as a failed attempt |
| `kora_police:server:escort`, `deEscort` | `target` | Escort start and stop |
| `kora_police:server:startDrag`, `stopDrag` | `target` | Drag start and stop |
| `kora_police:server:putInVehicle` | `target`, `netId`, `seat` | `seat` defaults to `-1` (driver) |
| `kora_police:server:takeOutVehicle` | `target` | |
| `kora_police:server:search` | `target` | Server answers with `kora_police:client:openSearch` |
| `kora_police:server:seizeCash`, `seizeDriverLicense` | `target` | |
| `kora_police:server:rob` | `target` | |
| `kora_police:server:bill` | `target`, `amount`, `reason` | |
| `kora_police:server:jailPlayer` | `target`, `minutes`, `reason` | |
| `kora_police:server:openArmory` | `shopId` | Answers with `kora_police:client:openArmory` |
| `kora_police:server:requestBackup` | none | Via `Kora.events` |
| `kora_police:server:panic` | none | Position is read server-side |
| `kora_police:server:crimeDetected` | incident key | Via `Kora.events`; allowed keys are the gunfire, suppressed gunfire, vehicle-theft and melee alerts |
| `kora_police:server:toggleDuty` | none | Via `Kora.events` |
| `kora_police:server:spawnDutyVehicle` | `plate`, `coords`, `heading` | Only `plate` is used; spawn position comes from config |
| `kora_police:server:storeDutyVehicle` | `plate` | |
| `kora_police:server:deploySpike`, `removeSpike` | `coords` / `netId` | Only the deploying officer can remove a strip |
| `kora_police:server:deleteNearestObject` | none | |
| `kora_police:server:flagPlate` | `plate`, `reason` | |
| `kora_police:server:unflagPlate`, `plateSpotted` | `plate` | |
| `kora_police:server:setTracker` | `target`, `active` | |
| `kora_police:server:sendTrackerLocation` | none | Tracked player reports its own position |
| `kora_police:server:impound` | `plate`, `lotId` | |
| `kora_police:server:retrieveImpound` | `plate` | |

## Client events (server to client)

| Event | Arguments | Meaning |
| --- | --- | --- |
| `kora_police:client:cuffed` | `cuffed`, `soft`, `otherSrc` | Cuff state; `otherSrc` is who cuffed or freed them |
| `kora_police:client:cuffAction` | `action`, `targetSrc` | Sent to the officer: `'cuff'` or `'uncuff'` |
| `kora_police:client:cuffedPlayerGone` | `serverId` | A cuffed player left; remove their handcuff prop |
| `kora_police:client:escortStart`, `escortStop` | `officer` / none | To the suspect |
| `kora_police:client:escortStartSelf`, `escortStopSelf` | `target` / none | To the officer |
| `kora_police:client:dragStart`, `dragStop`, `dragStartSelf`, `dragStopSelf` | player id | Same split for drag |
| `kora_police:client:putInVehicle`, `takeOutVehicle` | `netId`, `seat` / none | To the suspect |
| `kora_police:client:openSearch`, `openRob` | `target` | Opens the target's inventory |
| `kora_police:client:openArmory` | `shopId` | Opens the shop |
| `kora_police:client:updateCopCount` | `count` | On-duty LEO count, to on-duty LEO players |
| `kora_police:client:worldEvidenceCreated`, `worldEvidenceRemoved` | `id`, `type`, `coords` / `id` | Evidence markers |
| `kora_police:client:spikeDeployed`, `spikeRemoved` | `netId`, `coords` / `netId` | Spike strips (to all clients) |
| `kora_police:client:objectPlaced` | `id`, `netId`, `heading` | Road prop placed |
| `kora_police:client:setArmour` | `value` | Applies armour; ignored if fired by another local resource |
| `kora_police:client:requestTrackerPing` | none | Asks a tracked player to report its position |
| `kora_police:client:trackerLocation` | `target`, `coords` | To on-duty officers |
| `kora_police:client:flaggedPlateTriggered` | `plate`, `reason` | To on-duty officers |

## Local client event

`kora_police:client:cuffStateChanged(cuffed, soft, otherSrc)` is triggered locally whenever the client's cuff state changes.

## Server-side listeners

- `kora_inventory:server:weaponRoundFired(src, round)` creates a ballistic casing.
- `kora_inventory:server:sessionOpened` and `sessionClosed` track rob inventory sessions.
- `kora_inventory:server:ready` triggers the armory restock; a `kora_inventory` start re-registers shops, the evidence stash and armour useables.
- `kora_core:server:playerLoaded`, `QBCore:Server:OnPlayerUnload`, `QBCore:Server:SetDuty`, `QBCore:Server:OnJobUpdate` and `playerDropped` handle cuff sessions and cop counts.

## Callbacks (`Kora.callback`)

| Callback | Caller | Returns |
| --- | --- | --- |
| `kora_police:server:getCuffed` | anyone | Whether `target` (or the caller) is cuffed |
| `kora_police:server:beginBreakCuffs` | soft-cuffed player | A minigame authorisation, or `nil` and a reason |
| `kora_police:server:resyncCuff` | the cuffed player | `cuffed, soft` as the server holds them |
| `kora_police:server:cuffedPlayers` | any client | Sources currently cuffed |
| `kora_police:server:canAccessArmory` | anyone | `true`, or `false` and a reason |
| `kora_police:server:isPlateFlagged` | anyone | Whether the plate is flagged |
| `kora_police:server:getFingerprint` | on-duty officer, cuffed target in range | Fingerprint id or `nil` |
| `kora_police:server:getCops` | police | List of on-duty officer sources (empty table otherwise) |
| `kora_police:server:getPlayerStatus` | on-duty officer | Record with `citizenid`, `job`, `cuffed`, `tracked`, `escortedBy`, `draggedBy`, `status`; `nil` otherwise |
| `kora_police:armour:progress` (client) | server | Runs the armour progress bar |

The legacy callbacks (`police:GetCops`, `police:GetDutyPlayers`, ...) are listed in [Legacy compatibility](./compatibility.md).
