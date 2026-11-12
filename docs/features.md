---
title: Features
sidebar_position: 6
---

# Features

Server logic lives in the shared `Police` table (`server/core.lua`); feature files are thin wrappers around `Police.*` functions. See [Permissions](./permissions.md) for who may do what.

## Cuffing

- **Hard cuff**: an on-duty officer cuffs a player within `Config.cuff.distance` (target option **Cuff** or `kora_police:server:cuff`). A hard cuff cannot be escaped; an officer, or the `/uncuff` command, releases it.
- **Soft cuff**: using the `handcuffs` item cuffs the single other player within `Config.cuff.distance`. Anyone can use it, not only police. A soft-cuffed player can run `/breakcuffs` to attempt a server-authorised `mash` minigame (`Config.minigames.breakCuffs`); difficulty per attempt comes from `Config.cuff.breakCuffsDifficulty`, with `Config.cuff.breakCuffsAttempts` attempts and `Config.cuff.breakCuffsCooldown` after a failure.
- The restraint is stored in `kora_core` metadata `ishandcuffed` and mirrored to the player state bags `koraCuffed` and `koraCuffedSoft`. Only `server/cuff.lua` writes them (a client write is reverted).
- While cuffed the client keeps the cuff animation, blocks `Config.cuff.disabledControls`, disables the `kora_target` eye (`blockTargeting`), puts the weapon away (`holsterWeapon`) and closes `kora_phone` (`closePhone`). Handcuff props are drawn by each client from the state bag (`Config.cuff.prop`).
- A fresh cuff plays a paired animation on officer and suspect (`Config.cuff.anims`); the animation is cosmetic.
- A cuff lasts for the session it was applied in. Logout, character switch and disconnect end it, and a stale stored cuff is cleared at login unless `Config.cuff.restoreOnLogin` is `true` (then it returns as a hard cuff). If the resource restarts mid-session a cuff whose state bag is still set is kept.
- A client that finds itself cuffed asks the server to confirm (`Config.cuff.verifyWithServer`) and is freed if the server holds no cuff.
- Whoever soft-cuffed a player can release them (`Config.cuff.cufferCanUncuff`). Re-cuffing a cuffed player re-applies the restraint (`Config.cuff.recuffRefreshes`).

## Escort, drag and vehicles

- **Escort**: an on-duty officer walks a cuffed suspect (`/escort` toggles, or the **Escort** / **Stop Escorting** options).
- **Drag**: any player may drag a cuffed or downed target (`Config.incapacitated` decides what counts). Release with the `Config.drag.releaseKey` keybind (active only while dragging), `/releasedrag`, or the **Release** option. The server releases a drag when players separate by more than `Config.drag.autoReleaseDistance`, the dragger is downed, either player enters a vehicle (`releaseInVehicle`), or the target is no longer cuffed or downed (`releaseWhenRecovered`), checked every `Config.drag.checkInterval` ms.
- **Vehicle**: the **Put Suspect In Vehicle** option on a vehicle seats the escorted or dragged player; a seat can be chosen by the event (see [Events](./events.md)). Taking someone out is `kora_police:server:takeOutVehicle`.

## Search, seize and rob

- **Search** opens the target's inventory on the officer's client through `kora_inventory`'s inspection access; the server grants it only to on-duty police for a cuffed target.
- **Seize Cash** moves all of the target's cash to the officer; **Seize Driver's License** sets `metadata.licences.driver = false`. Both need a cuffed target within `Config.cuff.distance`.
- **Rob** (`Config.rob`): a player who is not on duty can rob a cuffed or downed player. It can take cash (capped at five times the largest value in `Config.fine.tiers`, 2500 with the defaults) and open their inventory for `Config.rob.accessSeconds`. Cash can be taken from the same player once per `robCooldownSeconds`. Access is closed when the target recovers or moves beyond `closeDistance`.

## Citations and jail

- **Issue Citation** asks for an amount (whole number, 1 to 100000) and reason. By default the citation is stored in the recipient's `citations` metadata (up to `Config.Citations.maxUnpaid`) until they pay it with `/paycitation`; with `autoDeduct` the fine is taken at once from `Config.fine.account`.
- **Book (Jail)** calls `exports.kora_core:jailPlayer` with the chosen minutes (default `Config.jail.defaultMinutes`) and clears escort, drag and cuff state.

## Evidence

- Casings: `kora_inventory` emits `kora_inventory:server:weaponRoundFired`; this resource creates a casing marker near the shooter and a row in `kora_police_ballistic_casings` (`Config.evidence.ballistic`). On-duty officers see markers (blip plus a **Collect ... evidence** option) and collecting one consumes `Config.evidence.bagItem` and gives a `filled_evidence_bag` with `caseId` info.
- Legacy world-evidence markers (blood, fingerprint, casing) are created at the caller's position by the `evidence:server:Create*` events. Markers expire after `worldMarkerTtl` and are capped by `maxWorldMarkers`.
- Collecting a non-ballistic marker through the **Collect** option (`evidence:server:AddToInventory`) records it as collected and removes the marker; it does not consume a bag or add an item. The stock `evidence:server:Add*ToInventory` events do consume an empty bag and add a filled one.
- Evidence locker: a `kora_inventory` stash (`Config.evidence.lockerStashId`) at `lockerCoords`, gated by `minGradeToAccess`.
- Ballistic rows are readable server-side through `GetBallisticCasing`; no client event exposes them.

## Armory

Each entry in `Config.armory.shops` is a `kora_inventory` shop with a `minGrade`. The target option shows only to on-duty officers of sufficient grade; the server re-checks job, grade and distance, and `kora_inventory` applies its own `groups` check. With `restockOnStart` (default `true`) missing configured rows are put back and rows below their configured `amount` are topped up when this resource starts.

## Body armour

`Config.armour.items` (`armor`, `armour`, `heavyarmor`) are usable: a cancellable progress bar, then the server removes one item and the client sets armour (`mode = 'set'` or `'add'`, capped at 100). `blockIfFull` refuses when armour would not rise. Set `enabled = false` to leave these items to another resource.

## Dispatch, panic and detectors

- `/backup` raises a backup call (`10-78`) through `kora_dispatch`, rate limited by `Config.dispatch.backupCooldown`.
- The panic key (`Config.dispatch.panicKey`, default `F10`) raises two calls: `10-99 Officer Down` to law enforcement and `10-52` to EMS (`Config.police.emsJobType`), with the position read server-side and a `panicCooldown` per officer.
- Detectors (client, every 500 ms, off-duty players only): shots fired (`10-31`, a suppressed variant at lower priority), vehicle theft (`10-16`) and fistfights (`10-10`), each throttled by its `Config.dispatch.*Cooldown`. The client sends only an incident key; wording, priority and position are server side.
- Backup and panic require on-duty `Config.police.jobType` (`leo`), so sheriff-type jobs work too. Department items (armory, evidence) use the job name `Config.police.job`.
- Cop counts (on-duty `leo` players) are broadcast on duty and job changes (see [Events](./events.md)).

## Duty and patrol fleet

Duty is toggled at a point from `Config.duty.points` (target option, `/police-duty`), only by a player whose job is `Config.police.job`. At start the resource creates a fleet row per entry in `Config.duty.vehicles` (plates `POLICE01`, `POLICE02`, ...) through `kora_core`'s garage. **Take Out** spawns it at its configured spot; **Store Patrol Vehicle** returns it.

## Spike strips and road props

- `/spikestrip` deploys a server-created networked strip a short way ahead (`Config.spikes`). Passing vehicles' tyres are popped client-side within `deflateDistance`. Strips are removed after `lifetime` ms.
- Cones, barriers, signs, tents and lights come from the legacy `police:client:spawn*` events and `Config.objects`: placed by the server in front of the officer, capped per officer, removed after `lifetime`.

## Plate flags, fingerprints, trackers, impound, cameras

- **Flag Plate / Unflag Plate** keep an in-memory plate registry (lost on restart) and, if `kora_mdt` is running, write or resolve an active vehicle BOLO in `kora_mdt_bolos`. An on-duty officer driving polls nearby plates and is alerted when a flagged plate is near.
- **Check Fingerprint** shows a 10-digit id generated once per citizen and kept in memory until the resource restarts.
- **Attach Tracker** marks a player; every 15 seconds tracked players report their position to on-duty officers as a map blip.
- **Impound Vehicle** (progress bar, `Config.impound.progress`) calls `kora_core` impound and deletes the vehicle; **Retrieve** at a lot (`Config.impound.lots`) lets the owner pay and reclaim.
- Cameras (`Config.cameras.list`) are viewed through legacy `police:client:ActiveCamera` events; there is no built-in menu.
- Door breach (`Config.breach`, `Config.minigames.breach`): a lockpick minigame unlocks a configured door for `unlockedFor` ms. It is off by default (`enabled = false`) and the lock state is handled client-side.
