---
layout: default
title: kora_police
---

Police/LEO job for FiveM. Cuffing (hard and soft, with a ported
`qbx_police`-style break-free skillcheck), escort/drag, vehicle loading,
suspect search and seizure, an evidence locker and legacy world-evidence
markers, a grade-gated armory, jail booking, dispatch alerts/backup requests,
duty toggling with a patrol-vehicle fleet, spike strips, plate flagging,
fingerprinting, GPS tracker bracelets, and vehicle impound. Restraint and
distance checks are server-authoritative `Police.*` Lua functions in
`server/core.lua`; feature files stay thin nets around them. Ships legacy
`police:*` event/callback compat (`server/compat/police.lua`) alongside the
modern `qbpolice:*` surface.

## Requirements

- [kora_lib](https://qbcore2.github.io/kora_lib/)
- [qbcore](https://qbcore2.github.io/kora_core/)
- [qbinventory](https://qbcore2.github.io/kora_inventory/)
- [qbtarget](https://qbcore2.github.io/kora_target/)

## Installation

`server.cfg`, in this order:
```
ensure kora_sql
ensure kora_lib
ensure kora_core
ensure kora_inventory
ensure kora_target
ensure kora_police
```

## Usage examples

### Cuff a suspect, then search them
```lua
-- client, e.g. a kora_target 'player' option
local target = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
TriggerServerEvent('qbpolice:server:cuff', target)
```
```lua
-- client, once the suspect is cuffed and in range (mirrors client/search.lua)
TriggerServerEvent('qbpolice:server:search', target)
```
`qbpolice:server:search` tells the OFFICER's own client to open the target's
inventory (`exports.kora_inventory:openInventory('player', targetServerId)`),
via `qbinventory:registerInspectionAccess`.

### Seize cash and a driver's licence
```lua
-- client, target must already be cuffed
TriggerServerEvent('qbpolice:server:seizeCash', target)
TriggerServerEvent('qbpolice:server:seizeDriverLicense', target)
```

### Escort a cuffed suspect, then load them into a vehicle
```lua
-- client
TriggerServerEvent('qbpolice:server:escort', target)
-- later, next to a networked vehicle:
local netId = NetworkGetNetworkIdFromEntity(vehicle)
TriggerServerEvent('qbpolice:server:putInVehicle', target, netId, -1) -- -1 = driver seat
```

### Book a suspect into jail
```lua
-- client, after cuffing -- also clears escort/drag state server-side
TriggerServerEvent('qbpolice:server:jailPlayer', target, 15, 'Resisting arrest')
```

### Raise a police call
```lua
-- client -- the /backup command already does this for an on-duty officer:
TriggerServerEvent('qbpolice:server:requestBackup', { message = 'Shots fired downtown' })
```

Anything else wanting a police call (a robbery script, a drug lab) calls
**kora_dispatch** directly rather than going through this resource:

```lua
-- server
exports.kora_dispatch:createCall({
    jobTypes = { 'leo' },   -- the whole law-enforcement service, not one job name
    code     = '10-90',
    title    = 'Bank Robbery',
    message  = 'Silent alarm at Fleeca, Legion Square.',
    priority = 1,
    coords   = coords,
    icon     = 'banknote',
})
```

Presentation — the feed, the map, history, the response state machine, the route
blip — belongs entirely to kora_dispatch. This resource no longer renders alerts;
see `kora_dispatch/docs/index.md`.

### Check restraint/armory access via a callback
```lua
-- client -- Kora.callback.trigger blocks and returns the server's result
local isCuffed = Kora.callback.trigger('qbpolice:server:getCuffed', target)

local canOpen = Kora.callback.trigger('qbpolice:server:canAccessArmory', 'pd-armory-sergeant')
if canOpen then TriggerServerEvent('qbpolice:server:openArmory', 'pd-armory-sergeant') end
```

## API reference

Restraint state, distances, and role checks (`Police.isPolice`,
`Police.isCuffed`, `Police.distanceBetween`, `Police.gradeLevel`) live as
plain Lua functions on the shared `Police` table (`server/core.lua`) and back
every net event below.

### Cuff / restrain
```lua
TriggerServerEvent('qbpolice:server:cuff', target)
TriggerServerEvent('qbpolice:server:uncuff', target)
TriggerServerEvent('qbpolice:server:breakCuffsResult', success)   -- client reports a soft-cuff escape attempt's outcome
Kora.callback.trigger('qbpolice:server:getCuffed', target)
```
Client: `RegisterNetEvent('qbpolice:client:cuffed', function(cuffed, soft, otherSrc) ... end)`,
`exports('IsHandcuffed')` (legacy, client-realm). The `handcuffs` useable item
soft-cuffs the single other player within `Config.cuff.distance`; a
soft-cuffed suspect runs `/breakcuffs` to attempt the ported
`qbx_police`-style escape skillcheck (`Config.cuff.breakCuffsDifficulty` /
`breakCuffsAttempts` / `breakCuffsCooldown`).

### Escort / drag / vehicle
```lua
TriggerServerEvent('qbpolice:server:escort', target)
TriggerServerEvent('qbpolice:server:deEscort', target)
TriggerServerEvent('qbpolice:server:startDrag', target)
TriggerServerEvent('qbpolice:server:stopDrag', target)
TriggerServerEvent('qbpolice:server:putInVehicle', target, netId, seat)  -- seat: native VehicleSeat, -1 = driver
TriggerServerEvent('qbpolice:server:takeOutVehicle', target)
```
Client events fired to the affected players:
`qbpolice:client:escortStart(Self)`, `escortStop(Self)`, `dragStart(Self)`,
`dragStop(Self)`, `putInVehicle`, `takeOutVehicle`.

### Search / seize
```lua
TriggerServerEvent('qbpolice:server:search', target)             -- opens target's inventory on the OFFICER's client
TriggerServerEvent('qbpolice:server:seizeCash', target)           -- moves target's cash account to the officer
TriggerServerEvent('qbpolice:server:seizeDriverLicense', target)  -- flags metadata.licences.driver = false
```

### Evidence
```lua
RegisterNetEvent('evidence:server:CreateBloodDrop', coords, citizenId)   -- legacy world-evidence markers
RegisterNetEvent('evidence:server:CreateFingerDrop', coords, citizenId)
RegisterNetEvent('evidence:server:CreateCasing', coords, citizenId)
RegisterNetEvent('evidence:server:AddToInventory', evidenceId)           -- on-duty officer collects a nearby marker
RegisterNetEvent('evidence:server:RemoveFromInventory', evidenceId)
RegisterNetEvent('evidence:server:ClearInventory')
```
A processed-evidence stash (`Config.evidence.lockerStashId`,
`'police-evidence'` by default) is registered on `exports.kora_inventory:RegisterStash`
at `Config.evidence.lockerCoords`, gated by `Config.evidence.minGradeToAccess`.
Client: `RegisterNetEvent('qbpolice:client:worldEvidenceCreated', function(id, evType, coords) ... end)`.

### Armory
```lua
TriggerServerEvent('qbpolice:server:openArmory', shopId)
Kora.callback.trigger('qbpolice:server:canAccessArmory', shopId)
```
Each `Config.armory.shops` entry is its own `exports.kora_inventory:RegisterShop`
room with `groups = { [Config.police.job] = shop.minGrade }` — grade 1
(Cadet) and up sees Patrol, grade 3+ Sergeant, grade 4+ SWAT. Client:
`RegisterNetEvent('qbpolice:client:openArmory', function(shopId) ... end)`.

### Jail
```lua
TriggerServerEvent('qbpolice:server:jailPlayer', target, minutes, reason)
```
Thin wrapper over `exports.kora_core:jailPlayer`; also clears the target's
escort/drag/cuff state on booking. `minutes` defaults to
`Config.jail.defaultMinutes`.

### Dispatch / duty
```lua
TriggerServerEvent('qbpolice:server:requestBackup', payload)   -- /backup command; payload: {title?, message?, coords?, ...}
TriggerServerEvent('qbpolice:server:toggleDuty')
TriggerServerEvent('qbpolice:server:spawnDutyVehicle', plate, coords, heading)
TriggerServerEvent('qbpolice:server:storeDutyVehicle', plate)
```
`Police.dispatch(payload)` (server Lua) raises a call through
`exports.kora_dispatch:createCall`, defaulting the target to the `Config.police.jobType`
**service** (`leo`) rather than a single job name — so a server that adds a
sheriff or state-trooper job with `type = 'leo'` gets them on the same radio with
no change here.

Cop-count changes broadcast `qbpolice:client:updateCopCount` (and legacy
`police:client:UpdateCurrentCops`/`SetCopCount`), counted across the whole LEO
service.

**Panic button** — `Config.dispatch.panicKey` (default `F10`, rebindable) fires
`qbpolice:server:panic`, which raises **two** calls: `10-99 Officer Down` to law
enforcement and `10-52` to EMS.

Rate-limited per officer by `Config.dispatch.panicCooldown` (default 60s),
server-side — a client-side gate would be a suggestion, since the net event is
reachable directly. One press is already two calls, so a mashed key would put
duplicates across both services' feeds at exactly the moment a clean feed
matters most. A suppressed press tells the officer their alarm is already
active rather than silently doing nothing. The cooldown clears when they go off
duty or disconnect.

Backup and panic gate on `Police.isLeo` (the job **type**), not
`Police.isPolice` (the job **name**): dispatch targets the whole LEO service, so
a sheriff's deputy already receives these calls and must be able to raise one
too. `Police.isPolice` remains the gate for department-specific things — this
force's armory and evidence lockers. They are separate incidents with separate wording
and separate histories; kora_dispatch refuses a single call targeting two services
for exactly this reason. Coordinates are read server-side from the officer's own
ped, never taken from the client.

**Detectors** — `client/detectors.lua` watches for shots fired, vehicle theft and
melee combat, each throttled by its own `Config.dispatch.*Cooldown`. On-duty
officers are excluded from every detector, so a firearms unit returning fire does
not alert dispatch about itself. The client decides *when*; the server decides
whether that player may raise a call and re-anchors it to their real position.

### Spikes / plate flags / tracker / fingerprint / impound
```lua
TriggerServerEvent('qbpolice:server:deploySpike', coords)   -- /spikestrip command
TriggerServerEvent('qbpolice:server:removeSpike', netId)
TriggerServerEvent('qbpolice:server:flagPlate', plate, reason)
TriggerServerEvent('qbpolice:server:unflagPlate', plate)
TriggerServerEvent('qbpolice:server:plateSpotted', plate)
Kora.callback.trigger('qbpolice:server:isPlateFlagged', plate)
TriggerServerEvent('qbpolice:server:setTracker', target, active)
TriggerServerEvent('qbpolice:server:sendTrackerLocation')
Kora.callback.trigger('qbpolice:server:getFingerprint', target)
TriggerServerEvent('qbpolice:server:impound', plate, lotId)
TriggerServerEvent('qbpolice:server:retrieveImpound', plate)
```

### MDT-ready callbacks (`server/callbacks.lua`)
No UI ships; these exist for a future MDT resource to consume directly:
```lua
Kora.callback.trigger('police:GetDutyPlayers')
Kora.callback.trigger('police:GetCops')
Kora.callback.trigger('police:isPlayerDead', target)
Kora.callback.trigger('police:IsSilencedWeapon', target)
Kora.callback.trigger('police:IsPoliceForcePresent', coords, radius)
Kora.callback.trigger('police:GetPlayerStatus', target)
Kora.callback.trigger('police:GetImpoundedVehicles')
Kora.callback.trigger('police:IsPlateFlagged', plate)
```

### Legacy `police:*` compat
`server/compat/police.lua` (loaded last) mirrors most of the above onto
Legacy police-style event and callback names — `police:server:CuffPlayer`,
`SearchPlayer`, `SeizeCash`, `EscortPlayer`, `KidnapPlayer`,
`PutPlayerInVehicle`, `BillPlayer`, `JailPlayer`/`SendToJail`, `RobPlayer`,
`SetTracker`, `Impound`/`TakeOutImpound`, `SyncSpikes`, and callbacks
`police:GetCuffed`, `police:GetEscorted`, `police:GetKidnappedTarget`,
`police:GetKidnappedDragger` — so existing scripts/UIs keep
working unmodified.

## Config highlights (`config.lua`)

`Config.police.job` (job name gate for every server check), `Config.cuff.*`
(cuff time/distance, break-free difficulty/attempts/cooldown),
`Config.evidence.*` (locker stash id/coords/grade gate, world-marker TTL and
cap), `Config.armory.shops` (per-room coords/`minGrade`/inventory),
`Config.jail.defaultMinutes`, `Config.dispatch.robberyRadius`,
`Config.dispatch.jobType`/`emsJobType`/`accent`/`panicKey`/`*Cooldown`,
`Config.duty.points`/`.vehicles` (duty toggle zones and patrol fleet spawns),
`Config.spikes.*`, `Config.impound.lots`, `Config.fine.tiers`/`.account`.

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [kora_lib](https://qbcore2.github.io/kora_lib/) — shared helper library
- [qbsql](https://qbcore2.github.io/kora_sql/) — database driver
- [qbcore](https://qbcore2.github.io/kora_core/) — framework core
- [qbinventory](https://qbcore2.github.io/kora_inventory/) — headless inventory
- [qbtarget](https://qbcore2.github.io/kora_target/) — targeting/interaction
- [qbambulance](https://qbcore2.github.io/kora_ambulance/) — EMS/ambulance job
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
