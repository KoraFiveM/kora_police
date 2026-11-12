---
title: Legacy compatibility
sidebar_position: 10
---

# Legacy compatibility

The manifest declares `provide 'qb-policejob'`, and `server/compat/police.lua`, `server/compat/stash.lua`, `client/compat.lua` and parts of the feature files register the stock `qb-policejob` event and callback names. They forward to the same `Police.*` functions as the native events, so the same checks apply. Where the stock behaviour was unsafe, the behaviour below differs from stock.

## Server events

| Event | Behaviour |
| --- | --- |
| `police:server:CuffPlayer(target)` | Officer cuff; the stock soft-cuff argument is ignored |
| `police:server:CuffPlayerSoft` | Handcuffs-item flow (nearest single player) |
| `police:server:SetHandcuffStatus(bool)` | Never changes state; the caller is re-sent the server state. The older `(target, cuffed)` officer form cuffs or uncuffs |
| `police:server:SearchPlayer`, `SeizeCash`, `SeizeDriverLicense` | Search and seize |
| `police:server:EscortPlayer`, `DeEscort`, `KidnapPlayer` | Escort and drag |
| `police:server:PutPlayerInVehicle`, `PutInVehicle` | Vehicle is the one given, or the nearest within 5 m |
| `police:server:SetPlayerOutVehicle`, `SetOutVehicle` | Take out of vehicle |
| `police:server:BillPlayer`, `JailPlayer`, `SendToJail`, `RobPlayer` | Citation, jail and rob flows |
| `police:server:UpdateCurrentCops`, `SetCopCount`, `UpdateBlips` | Re-broadcast cop count, one throttle per player (`Config.dispatch.copCountThrottle`) |
| `police:server:policeAlert(text)` | One `10-60 Police Alert` call at the caller's server-side position; text is sanitised and capped, rate limited per player |
| `police:server:showFingerprint`, `showFingerprintId` | Officer gets the target's fingerprint id |
| `police:server:SetTracker(target)` | Toggles the tracker (officer, on duty, in range) |
| `police:server:SendTrackerLocation(_, requestId)` | Tracked player replies to an on-duty requester using its own position |
| `police:server:TrackerMessage(target, message)` | On-duty officer relays a message (160 characters) about a tracked player to on-duty officers |
| `police:server:FlaggedPlateTriggered(coords, plate)` | Sender must be an on-duty officer and the plate flagged; `coords` ignored; 1 s throttle |
| `police:server:Impound(plate, fullImpound, price)` | `price` becomes the fee, capped by `Config.impound.maxFee`; vehicle condition is read on the server |
| `police:server:TakeOutImpound(plate, garage)` | Caller must be at the lot and the owner; pays the fee |
| `police:server:spawnObject(arg)` | A string places a road prop (`Config.objects.types`); anything else deploys a spike strip |
| `police:server:deleteObject(id)` | Removes a prop within `Config.objects.deleteDistance` |
| `police:server:SyncSpikes(netId, false)` | Only the owning officer removing a strip; stock table syncs are ignored |
| `heli:server:spotlight(state)` | On-duty LEO in the front seats of a helicopter; boolean only; rebroadcast as `heli:client:spotlight` |
| `qb-policejob:server:stash`, `trash`, `evidence` | On-duty police only; stash ids `policestash_` plus citizen id, `policetrash`, and the stock room-and-drawer id for evidence; evidence ids are parsed against `Config.evidence.drawers` |

## Evidence events

`evidence:server:CreateBloodDrop`, `CreateFingerDrop` and `CreateCasing` ignore every argument and create a marker at the caller's position (one per `Config.evidence.createCooldown`). `AddToInventory`, `RemoveFromInventory` and `ClearInventory` manage the per-officer collected list. `AddBlooddropToInventory`, `AddFingerprintToInventory` and `AddCasingToInventory` consume an empty bag and add a filled one with server-built info. `ClearBlooddrops` and `ClearCasings` remove nearby markers of that type. `UpdateStatus` keeps only ids in `Config.evidence.statuses`, for `Config.evidence.statusTtl` ms.

## Callbacks

| Callback | Notes |
| --- | --- |
| `police:GetCops` | On-duty LEO count, to any caller |
| `police:GetDutyPlayers` | Stock `source`, `label`, `job` entries to anyone; `citizenid`, `name`, `grade` only for police callers |
| `police:isPlayerDead`, `police:server:isPlayerDead` | Non-police callers may only ask about themselves or someone within `Config.cuff.distance` |
| `police:IsSilencedWeapon` | A weapon hash or name checks the caller's own selected weapon; a small number is the older target-id form (police only) |
| `police:IsPoliceForcePresent(coords, radius)` | Police callers only: any on-duty police within radius |
| `police:server:IsPoliceForcePresent` | Any caller: on-duty LEO of grade level 2 or higher exists |
| `police:GetPlayerStatus` | Status text list; on-duty officer, target within `Config.evidence.statusDistance` |
| `police:GetImpoundedVehicles` | Police only; plates impounded by this resource since its start |
| `police:IsPlateFlagged`, `police:server:IsPlateFlagged` | Police only |
| `police:GetCuffed`, `police:GetEscorted`, `police:GetKidnappedTarget`, `police:GetKidnappedDragger` | State lookups |

## Client events

- Initiators (`police:client:CuffPlayer`, `CuffPlayerSoft`, `SeizeCash`, `SeizeDriverLicense`, `RobPlayer`, `PutPlayerInVehicle`, `SetPlayerOutVehicle`, `EscortPlayer`, `KidnapPlayer`, `JailPlayer`, `BillPlayer`) pick the nearest player and forward to the matching server event.
- Victim-side events (`police:client:GetCuffed`, `GetEscorted`, `DeEscort`, `GetKidnappedTarget`, `GetKidnappedDragger`, `PutInVehicle`, `SetOutVehicle`) and `SendToJail`, `TakeOutVehicle`, `VehicleMenuHeader`, `ImpoundMenuHeader`, `qb-police:client:spawnHelicopter` only show a "not supported" notification.
- Road props: `police:client:spawnCone`, `spawnBarrier`, `spawnRoadSign`, `spawnTent`, `spawnLight`, `deleteObject`.
- Cameras: `police:client:ActiveCamera(id)` (0 closes), `DisableAllCameras`, `EnableAllCameras`, `SetCamera`.
- Other: `police:client:SendPoliceEmergencyAlert` (panic), `policeAlert`, `CheckStatus`, `ImpoundVehicle`, `TakeOutImpound`, `EvidenceStashDrawer`, `CheckDistance`, `SpawnSpikeStrip`, `SetTracker`, `TrackerMessage`, `SendTrackerLocation`, `qb-police:client:scanFingerPrint`, `qb-policejob:ToggleDuty`.
- Cop count is delivered as `police:SetCopCount` (to everyone) and `police:client:UpdateCurrentCops` / `SetCopCount` (to on-duty LEO).
- Fired by this resource: `police:client:SyncSpikes`, `police:client:spawnObject` (spike strip), `police:client:FlaggedPlateTriggered`, `police:client:TrackerMessage`, `qb-phone:client:addPoliceAlert`, `QBCore:Notify`.

## Exports

`exports['qb-policejob']:IsHandcuffed` is provided on the client through `Kora.compat.provideExport`.
