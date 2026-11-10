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
modern `kora_police:*` surface.

## Requirements

- [kora_lib](https://qbcore2.github.io/kora_lib/)
- [kora_core](https://qbcore2.github.io/kora_core/)
- [kora_inventory](https://qbcore2.github.io/kora_inventory/)
- [kora_target](https://qbcore2.github.io/kora_target/)

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
TriggerServerEvent('kora_police:server:cuff', target)
```
```lua
-- client, once the suspect is cuffed and in range (mirrors client/search.lua)
TriggerServerEvent('kora_police:server:search', target)
```
`kora_police:server:search` tells the OFFICER's own client to open the target's
inventory (`exports.kora_inventory:openInventory('player', targetServerId)`),
via `kora_inventory:registerInspectionAccess`.

### Seize cash and a driver's licence
```lua
-- client, target must already be cuffed
TriggerServerEvent('kora_police:server:seizeCash', target)
TriggerServerEvent('kora_police:server:seizeDriverLicense', target)
```

### Escort a cuffed suspect, then load them into a vehicle
```lua
-- client
TriggerServerEvent('kora_police:server:escort', target)
-- later, next to a networked vehicle:
local netId = NetworkGetNetworkIdFromEntity(vehicle)
TriggerServerEvent('kora_police:server:putInVehicle', target, netId, -1) -- -1 = driver seat
```

### Book a suspect into jail
```lua
-- client, after cuffing -- also clears escort/drag state server-side
TriggerServerEvent('kora_police:server:jailPlayer', target, 15, 'Resisting arrest')
```

### Raise a police call
```lua
-- client -- the /backup command already does this for an on-duty officer:
TriggerServerEvent('kora_police:server:requestBackup', { message = 'Shots fired downtown' })
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
local isCuffed = Kora.callback.trigger('kora_police:server:getCuffed', target)

local canOpen = Kora.callback.trigger('kora_police:server:canAccessArmory', 'pd-armory-sergeant')
if canOpen then TriggerServerEvent('kora_police:server:openArmory', 'pd-armory-sergeant') end
```

## API reference

Restraint state, distances, and role checks (`Police.isPolice`,
`Police.isCuffed`, `Police.distanceBetween`, `Police.gradeLevel`) live as
plain Lua functions on the shared `Police` table (`server/core.lua`) and back
every net event below.

### Cuff / restrain
```lua
TriggerServerEvent('kora_police:server:cuff', target)
TriggerServerEvent('kora_police:server:uncuff', target)
TriggerServerEvent('kora_police:server:breakCuffsResult', success)   -- client reports a soft-cuff escape attempt's outcome
Kora.callback.trigger('kora_police:server:getCuffed', target)
```
Client: `RegisterNetEvent('kora_police:client:cuffed', function(cuffed, soft, otherSrc) ... end)`
(`otherSrc` is the player who just cuffed or uncuffed them, nil for a re-cuff,
an escape, a booking or a login clean-up),
`RegisterNetEvent('kora_police:client:cuffAction', function(action, targetSrc) ... end)`
(sent to that player: `action` is `'cuff'` or `'uncuff'`),
`exports('IsHandcuffed')` (legacy, client-realm). The `handcuffs` useable item
soft-cuffs the single other player within `Config.cuff.distance`; a
soft-cuffed suspect runs `/breakcuffs` to attempt the ported
`qbx_police`-style escape skillcheck (`Config.cuff.breakCuffsDifficulty` /
`breakCuffsAttempts` / `breakCuffsCooldown`).

The restraint is stored once, in kora_core metadata `ishandcuffed` (what
`Police.isCuffed` reads, and what persists), and the server mirrors it onto the
replicated player state bag: `Player(src).state.koraCuffed` (boolean) and
`koraCuffedSoft`. Only `server/cuff.lua` writes them (a client write is put
back); clients, `kora_emotemenu` and `kora_inventory` only read them. While the
bag says cuffed the client keeps the cuff animation (checked every
`Config.cuff.animCheckInterval` ms, only while cuffed), holds
`Config.cuff.disabledControls` through a kora_lib control lease, switches the
kora_target eye off through its `setEnabled` export so no target option works
(vehicles, trunks, doors, ...; `Config.cuff.blockTargeting`), and the emote
menu, inventory and hotbar refuse to open. At the start of a cuff the weapon in
hand is put away (`Config.cuff.holsterWeapon`) and kora_phone is closed
(`Config.cuff.closePhone`).

When a player cuffs someone who was not cuffed, both play the paired cuff
animation from `Config.cuff.anims.cuff` (by default `mp_arrest_paired`
`cop_p2_back_left` / `crook_p2_back_left`, stopped at 3043 ms): the officer on
their own client, the suspect on theirs, attached in front of the officer for
the first 950 ms so the pair lines up (`attach`: bone, offset, rotation, ms),
then the cuffed idle takes over. An uncuff by another player plays `Config.cuff.anims.uncuff` on both
(`mp_arresting` `b_uncuff` for the officer, `a_uncuff` for the suspect). The
animations are only cosmetic: the server has already put the cuff on or taken it
off when they start, and they only play on foot and not downed (kora_ambulance's
`emsDown` bag: `'laststand'`/`'dead'` is downed, `false` is alive). The suspect is
told `Config.cuff.notify.cuffed` / `.uncuffed` ("You have been uncuffed and are
free."); `''` turns a message off.

Every cuffed player wears handcuffs on their wrists (`Config.cuff.prop`, default
`p_cs_cuffs_02_s` on ped bone 60309, the left wrist), seen by every player. Each
client draws them itself from the replicated `koraCuffed` bag instead of one
networked object, so they also work under `sv_entityLockdown strict` and can
never be orphaned. `bone` is a ped bone id (a name such as `PH_L_Hand` is turned
into its id: MP peds do not reliably resolve bone names); a prop that cannot be made is
reported once in F8. A
client checks every `Config.cuff.prop.checkInterval` ms, and only while someone
is cuffed, for cuffed players coming into view or respawning. The cuffs go when
the cuff does, when the player leaves view or disconnects, and when this
resource stops. A cuff (and so its prop) stays on through death. Cuffing someone who is already cuffed
re-applies the restraint (`Config.cuff.recuffRefreshes`); an officer's cuff
hardens a soft one. Uncuff works on anyone cuffed: an on-duty officer, the
player who soft-cuffed them (`Config.cuff.cufferCanUncuff`), or `/uncuff`
(`Config.cuff.uncuffCommand`) for the nearest cuffed player. A cuff lasts for the
session it was put on in: logout, character switch and disconnect end it, and a
cuff still stored in the metadata is cleared at the next login. Set
`Config.cuff.restoreOnLogin = true` (anti-combat-log, off by default) to bring a
stored cuff back as a hard cuff instead. A client that finds itself cuffed by the
bag, or cannot show the cuff animation, asks the server once to confirm and
is freed if the server holds no cuff for it (`Config.cuff.verifyWithServer`).
An uncuff (any path: target option, `/uncuff`, an escape, a release on booking)
takes everything off on the freed player's own client straight away: the control
lease, the kora_target block, the prop, the handcuffed ped flag and the cuff animation (and, with
`Config.cuff.clearTasksOnUncuff`, the ped's tasks when on foot and not downed),
so every other client sees it stop too. `Config.cuff.uncuffRecheckMs` (default
1000, 0 = off) checks once more after that and removes anything still left. An
escort of the freed player ends with the cuff.

Robbing a restrained or downed player takes their cash at most once per
`Config.rob.robCooldownSeconds` per target; the cooldown does not stop the
robber searching the inventory.

### Escort / drag / vehicle
```lua
TriggerServerEvent('kora_police:server:escort', target)
TriggerServerEvent('kora_police:server:deEscort', target)
TriggerServerEvent('kora_police:server:startDrag', target)
TriggerServerEvent('kora_police:server:stopDrag', target)
TriggerServerEvent('kora_police:server:putInVehicle', target, netId, seat)  -- seat: native VehicleSeat, -1 = driver
TriggerServerEvent('kora_police:server:takeOutVehicle', target)
```
Client events fired to the affected players:
`kora_police:client:escortStart(Self)`, `escortStop(Self)`, `dragStart(Self)`,
`dragStop(Self)`, `putInVehicle`, `takeOutVehicle`.

### Search / seize
```lua
TriggerServerEvent('kora_police:server:search', target)             -- opens target's inventory on the OFFICER's client
TriggerServerEvent('kora_police:server:seizeCash', target)           -- moves target's cash account to the officer
TriggerServerEvent('kora_police:server:seizeDriverLicense', target)  -- flags metadata.licences.driver = false
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
Client: `RegisterNetEvent('kora_police:client:worldEvidenceCreated', function(id, evType, coords) ... end)`.

### Armory
```lua
TriggerServerEvent('kora_police:server:openArmory', shopId)
Kora.callback.trigger('kora_police:server:canAccessArmory', shopId)
```
Each `Config.armory.shops` entry is its own `exports.kora_inventory:RegisterShop`
room with `groups = { [Config.police.job] = shop.minGrade }` — grade 1
(Cadet) and up sees Patrol, grade 3+ Sergeant, grade 4+ SWAT. Client:
`RegisterNetEvent('kora_police:client:openArmory', function(shopId) ... end)`.
kora_inventory saves shop stock across restarts, so with `Config.armory.restockOnStart`
(default `true`) every start of kora_police puts back configured items a saved room is
missing and tops rows up to their `amount`; a kora_inventory restart mid-session does not.
The Patrol room issues `empty_evidence_bag` (`Config.evidence.bagItem`), which collecting
casings, blood and fingerprints consumes.

### Jail
```lua
TriggerServerEvent('kora_police:server:jailPlayer', target, minutes, reason)
```
Thin wrapper over `exports.kora_core:jailPlayer`; also clears the target's
escort/drag/cuff state on booking. `minutes` defaults to
`Config.jail.defaultMinutes`.

### Dispatch / duty
```lua
TriggerServerEvent('kora_police:server:requestBackup', payload)   -- /backup command; payload: {title?, message?, coords?, ...}
TriggerServerEvent('kora_police:server:toggleDuty')
TriggerServerEvent('kora_police:server:spawnDutyVehicle', plate, coords, heading)
TriggerServerEvent('kora_police:server:storeDutyVehicle', plate)
```
`Police.dispatch(payload)` (server Lua) raises a call through
`exports.kora_dispatch:createCall`, defaulting the target to the `Config.police.jobType`
**service** (`leo`) rather than a single job name — so a server that adds a
sheriff or state-trooper job with `type = 'leo'` gets them on the same radio with
no change here.

Cop-count changes broadcast `kora_police:client:updateCopCount` (and legacy
`police:client:UpdateCurrentCops`/`SetCopCount`), counted across the whole LEO
service.

**Panic button** — `Config.dispatch.panicKey` (default `F10`, rebindable) fires
`kora_police:server:panic`, which raises **two** calls: `10-99 Officer Down` to law
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
TriggerServerEvent('kora_police:server:deploySpike', coords)   -- /spikestrip command
TriggerServerEvent('kora_police:server:removeSpike', netId)
TriggerServerEvent('kora_police:server:flagPlate', plate, reason)
TriggerServerEvent('kora_police:server:unflagPlate', plate)
TriggerServerEvent('kora_police:server:plateSpotted', plate)
Kora.callback.trigger('kora_police:server:isPlateFlagged', plate)
TriggerServerEvent('kora_police:server:setTracker', target, active)
TriggerServerEvent('kora_police:server:sendTrackerLocation')
Kora.callback.trigger('kora_police:server:getFingerprint', target)
TriggerServerEvent('kora_police:server:impound', plate, lotId)
TriggerServerEvent('kora_police:server:retrieveImpound', plate)
```

### MDT-ready callbacks (`server/callbacks.lua`)
No UI ships; these exist for a future MDT resource to consume directly:
```lua
Kora.callback.trigger('police:GetDutyPlayers')
Kora.callback.trigger('police:GetCops')                    -- stock: a NUMBER, any caller
Kora.callback.trigger('kora_police:server:getCops')           -- kora: list of on-duty officer sources (police callers only)
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

#### Stock qb-policejob parity

*Callbacks.* `police:GetCops` returns the on-duty LEO **count** to any caller, as
stock does; the old list lives at `kora_police:server:getCops` (police only).
`police:GetDutyPlayers` is open to any caller with the stock `{ source, label,
job }` shape; `citizenid`/`name`/`grade` are added for police callers only.
`police:server:isPlayerDead`, `police:server:IsPoliceForcePresent` and
`police:server:IsPlateFlagged` are registered under their stock names (the old
names stay). Deviations: a non-police caller may only ask `isPlayerDead` about
themself or someone within `Config.cuff.distance`; `IsPoliceForcePresent`
counts only **on-duty** grade-2+ officers; `IsPlateFlagged` stays
officer-only. `police:IsSilencedWeapon` takes a weapon hash/name (stock) and
checks the caller's own selected inventory weapon; a small number is still
read as the old target player id (police only).

*Events.* `police:server:policeAlert(text)` raises one `10-60 Police Alert`
through kora_dispatch at the caller's **server-side** position; text is
sanitised and capped (`Config.dispatch.legacyAlertMaxLength`), one per player per
`Config.dispatch.legacyAlertCooldown`. kora_core's own local mirror of a dispatch
alert (same event name) is recognised by its message (via `kora_core:server:dispatchAlert`,
1 s window) and dropped, so it never creates a duplicate call. `police:server:FlaggedPlateTriggered(coords, plate)`
follows the stock argument order; the sender must be an on-duty officer and the
plate must really be flagged (`coords` is ignored). `police:server:SetHandcuffStatus(bool)`
never changes cuff state — the server owns it and just re-syncs the caller.
The cop count is broadcast to all clients as `police:SetCopCount(count)`
(plus the older cop-only `police:client:*` events); `UpdateCurrentCops`,
`SetCopCount` and `UpdateBlips` server events share one throttle per
source (`Config.dispatch.copCountThrottle`). `police:server:CuffPlayer`'s `isSoftcuff`
is ignored: an officer's cuff is always the unescapable kind.
`police:server:PutPlayerInVehicle(target)` (stock sends no vehicle) uses the
vehicle nearest the officer, within 5 m, with all the usual cuff/distance checks.

*Client interaction events.* The 18 events in stock `client/interactions.lua`
are registered. Initiators (`CuffPlayer`, `CuffPlayerSoft`, `EscortPlayer`,
`KidnapPlayer`, `PutPlayerInVehicle`, `SetPlayerOutVehicle`, `SeizeCash`,
`SeizeDriverLicense`, `RobPlayer`, `JailPlayer`, `BillPlayer`) pick the nearest
player and forward to the stock `police:server:*` event, i.e. onto kora's own
flows with kora's server checks (`EscortPlayer`/`KidnapPlayer` release the
current target when fired again; `CuffPlayerSoft` is the handcuffs-item flow).
The victim-side events (`GetCuffed`, `GetEscorted`, `DeEscort`,
`GetKidnappedTarget`, `GetKidnappedDragger`, `PutInVehicle`, `SetOutVehicle`) have
no kora equivalent — kora never lets a client set its own cuff/escort/seat state
— so they only show a "not supported" notification.

*Second pass (stash, props, evidence, tracker, impound, cameras).*
- `qb-policejob:server:stash` / `trash` / `evidence`: on-duty police only. Stash ids keep the stock names
  (`policestash_<citizenid>`, `policetrash`, `<room> | Drawer <n>`); the evidence id is parsed against
  `Config.evidence.drawers` (rooms, max drawer, distance) and never used as sent. `Config.stash.locations`
  (empty = no distance check, like stock) adds a distance gate; `Config.stash.clearTrashOnStart` wipes the trash stash on start.
- Road props: `police:client:spawnCone/Barrier/RoadSign/Tent/Light` and `deleteObject` ask the server
  (`police:server:spawnObject(type)` / `deleteObject(id)`), which creates and removes the prop at the officer's position
  (`Config.objects`: types, per-officer cap, lifetime, delete distance). `police:server:spawnObject(coords)` still deploys a spike strip;
  `police:client:SpawnSpikeStrip` = `/spikestrip`. Stock `SyncSpikes(table)` is a no-op (strips are server-owned).
- `heli:server:spotlight(state)`: on-duty LEO seated in a helicopter, boolean state, rebroadcast as `heli:client:spotlight`.
- `SetTracker` now toggles (and mirrors `metadata.tracker`); `SendTrackerLocation(coords, requestId)` replies to an on-duty requester
  using the caller's own position. `police:client:TrackerMessage` accepts stock `(msg, coords)` and kora `(target, msg)`.
- `evidence:server:Add{Blooddrop,Fingerprint,Casing}ToInventory` consume an empty bag and add a filled one with server-built metadata
  (client `info` ignored); `ClearBlooddrops` / `ClearCasings` remove nearby markers of that type (officers only);
  `UpdateStatus` keeps only ids in `Config.evidence.statuses`. `police:GetPlayerStatus` returns the stock list of texts (officer, in reach);
  the old record is `kora_police:server:getPlayerStatus`.
- `police:server:Impound(plate, fullImpound, price, ...)`: price becomes the fee (capped by `Config.impound.maxFee`); body/engine come from the
  vehicle, not the client. `TakeOutImpound(plate, lotIndex)` needs the caller at the lot and goes through the owner-only retrieval.
- `police:server:RobPlayer` runs the same `Police.rob` flow as the kora rob key (`Config.rob`: cash, then the target's inventory through
  the shared inspection grant; restrained or downed targets in reach only; the stock hands-up state is client-only and not honoured).
- Cameras: `Config.cameras`, `police:client:ActiveCamera/DisableAllCameras/EnableAllCameras/SetCamera` (local view only).
- Job events: `SendPoliceEmergencyAlert` (panic), `policeAlert` (both argument orders), `CheckStatus`, `ImpoundVehicle`, `TakeOutImpound`,
  `EvidenceStashDrawer`, `CheckDistance`, `qb-police:client:scanFingerPrint`, `qb-policejob:ToggleDuty`.
  `SendToJail`, `TakeOutVehicle`, `VehicleMenuHeader`, `ImpoundMenuHeader` and `qb-police:client:spawnHelicopter` only show "not supported".

## Config highlights (`config.lua`)

`Config.police.job` (job name gate for every server check), `Config.cuff.*`
(cuff time/distance, break-free difficulty/attempts/cooldown),
`Config.rob.*` (takeCash/openInventory, inventory access seconds, close distance), `Config.drag.*`
(release key/command/optional polled control/hint, auto-release distance/vehicle/recovery, attach bone/offset/rotation; the release key is a kora_lib keybind enabled only while dragging, so E does nothing otherwise, release is silent when nothing is dragged, and the Release option shows on any aimed player, ped or vehicle while dragging),
`Config.evidence.*` (locker stash id/coords/grade gate, world-marker TTL and
cap), `Config.armory.shops` (per-room coords/`minGrade`/inventory),
`Config.jail.defaultMinutes`, `Config.dispatch.robberyRadius`,
`Config.dispatch.jobType`/`emsJobType`/`accent`/`panicKey`/`*Cooldown`,
`Config.dispatch.legacyAlertCooldown`/`legacyAlertMaxLength`/`copCountThrottle`,
`Config.duty.points`/`.vehicles` (duty toggle zones and patrol fleet spawns),
`Config.spikes.*`, `Config.impound.lots`, `Config.plateFlags` (mirrorToMdt/days: Flag/Unflag Plate write and resolve a vehicle BOLO in kora_mdt), `Config.impound.progress` (enabled/duration/label/canCancel/anim/prop for the impound progress bar), `Config.fine.tiers`/`.account`.

### Body armour (`Config.armour`)

`armor` (the item the armory hands out), `armour` (alias for existing stock) and `heavyarmor` are registered as usable items. Using one shows a cancellable progress bar, then the server removes one item and sets armour to the item's `amount` (`mode = 'add'` adds instead; both cap at 100). `blockIfFull` keeps the item when it would not raise armour; `enabled = false` leaves the items to another resource.

### Citations

An issued citation is stored on the recipient (metadata `citations`) until paid, and the recipient is told how to pay it. Options in `Config.Citations`:

- `autoDeduct` (default `false`): `true` charges `Config.fine.account` immediately on issue and stores nothing.
- `payMethods.command` (default `true`): `/citations` lists unpaid citations, `/paycitation [number]` pays one (names via `listCommand` / `payCommand`).
- `payMethods.exports` (default `true`): `exports.kora_police:getCitations(src)` and `exports.kora_police:payCitation(src, id)` for a phone or bank UI to call.
- `maxUnpaid` (default `25`): oldest citation is dropped beyond this.

Refused cuff / uncuff / citation actions (not on duty, too far, already cuffed, ...) now notify the officer instead of doing nothing.


## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [kora_lib](https://qbcore2.github.io/kora_lib/) — shared helper library
- [kora_sql](https://qbcore2.github.io/kora_sql/) — database driver
- [kora_core](https://qbcore2.github.io/kora_core/) — framework core
- [kora_inventory](https://qbcore2.github.io/kora_inventory/) — headless inventory
- [kora_target](https://qbcore2.github.io/kora_target/) — targeting/interaction
- [kora_ambulance](https://qbcore2.github.io/kora_ambulance/) — EMS/ambulance job
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
