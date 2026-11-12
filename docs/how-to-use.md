---
title: "How to use"
sidebar_position: 3
---


# How to use

Kora Police supplies the LEO job on top of kora_core (job/duty), kora_inventory (every item, shop and stash), kora_target (every interaction) and kora_dispatch (every call). It keeps the full legacy qb-policejob/qbx_police event surface working (see Legacy compatibility & MDT readiness in Function modules) while adding real differentiators: a door-breach lockpick minigame, a skillcheck-based cuff escape, durable ballistic forensics, and an MDT-ready callback surface.

## Permission model: job, duty, grade — verified from source, not assumed

- **Every mutating server function gates on `Police.isPolice(src, onDutyOnly?)`**, which requires the caller's `kora_core` job to be `Config.police.job` (default `police`) AND (unless `onDutyOnly` is explicitly `false`) on duty — cuff, uncuff (officer path), escort, drag (starter is NOT required to be police — see below), search, seize cash/license, bill, jail, impound, armory access, spike/prop placement, duty-vehicle spawn/store, tracker toggle, plate flag/unflag. There is no separate ACE/admin layer in this resource: job + duty + grade (for armory/evidence) is the entire permission model.
- **Drag (`Police.startDrag`) and robbery (`Police.rob`) are deliberately NOT job-gated** — anyone can drag or rob an incapacitated player (cuffed or downed, per `Config.incapacitated`), matching the stock qb-policejob/qbx_police behavior that robbery is a player-vs-player mechanic, not an officer power. Escort, by contrast, DOES require `Police.isPolice` on the escorting side (only an officer may walk a cuffed suspect).
- **Self-cuffing is blocked** (`officerSrc == targetSrc` is refused) and **a restrained officer cannot act**: `Police.cuff`/`Police.rob` both refuse when the ACTOR is already cuffed (`you are restrained`), so a suspect who manages to get an officer cuffed cannot then be cuffed/robbed by that disabled officer.
- **Distance is re-checked server-side on every action**, independent of what kora_target let the client attempt: `Config.cuff.distance` (default 2.5m) for cuff/uncuff/escort/drag/search/seize/bill/tracker/put-in-vehicle, plus resource-specific radii for spikes, props, duty points, armory and impound/duty vehicles.
- **`Police.isPolice` (job NAME) vs `Police.isLeo` (job TYPE)**: armory, evidence, jail, citations and duty actions use `isPolice` (this force only). Dispatch — panic, backup, crime detection — uses `isLeo`, which passes for ANY on-duty job whose `kora_core` job type is `Config.police.jobType` (default `leo`), so a `sheriff` or `statetrooper` job of the same type can also raise/receive those calls without code changes here.
- **Legacy compat events never relax a check**: every `server/compat/police.lua` and `server/compat/stash.lua` handler forwards into the same `Police.*` functions the native events use, so a third-party script calling the old qb-policejob event name is held to the identical job/duty/grade/distance rules as the native one.

## Grade ladder

- Grades are 1-based and defined by the `police` job in `kora_core/shared/jobs.lua`: Cadet=1, Officer=2, Sergeant=3, Lieutenant=4, Chief=5 (the config's own comment names this exact ladder). `Police.gradeLevel(src)` returns `-1` for anyone not employed by `Config.police.job`.
- Armory rooms are gated per-shop by `minGrade` (`Config.armory.shops[].minGrade`): Patrol Armory needs grade 1 (everyone), Sergeant Armory needs grade 3+, SWAT Armory needs grade 4+. The gate is enforced twice — this resource's own `Police.canAccessArmory` (checked before the client is even told the shop opened) and kora_inventory's own `RegisterShop` `groups` policy (`{ [Config.police.job] = shop.minGrade }`), so a bypass of the first still hits the second.
- The evidence locker needs `Config.evidence.minGradeToAccess` (default 1 — everyone). Evidence drawers (the legacy `qb-policejob:server:evidence` stash family) use the same `minGradeToAccess`.

## Fingerprints: current, verified behavior

A fingerprint-generator bug (garbage/variable-length output) was previously reported and has been fixed; the implementation below is what `server/fingerprint.lua` contains today.

```lua title="server/fingerprint.lua" {1,7,8,9,10,11}
local CHARS = '0123456789'

function Police.getFingerprint(citizenId)
    if Police.fingerprints[citizenId] then return Police.fingerprints[citizenId] end
    local id = {}
    for i = 1, 10 do
        local pick = math.random(1, #CHARS)
        id[i] = CHARS:sub(pick, pick)
    end
    local fingerprint = table.concat(id)
    Police.fingerprints[citizenId] = fingerprint
    return fingerprint
end
```

- `Police.getFingerprint(citizenId)` (`server/fingerprint.lua`) generates a **fixed-length, 10-character numeric string** the first time it is asked for a given citizenid: a loop of `math.random(1, #CHARS)` over `CHARS = '0123456789'` picks one digit per position, `table.concat` joins the 10 picks, and the result is cached in `Police.fingerprints[citizenId]` for the life of the server process. Every later call for the same citizenid returns the identical cached string — deterministic per person for that server run, never regenerated, never variable-length. It is NOT persisted to the database (matches qb-policejob's own throwaway-session-data behavior for this value) — a resource or server restart clears `Police.fingerprints` and the next request mints a fresh id for that citizenid.
- `Police.getFingerprintForOfficer(officerSrc, targetSrc)` is the only path that actually reveals a fingerprint: it requires the caller to be `Police.isPolice`, the target to be currently cuffed (`Police.isCuffed`), and both within `Config.cuff.distance` — then returns `Police.getFingerprint(citizenId)` for the target. The `fingerprint` kora_target option on a cuffed player (client/fingerprint.lua, label "Check Fingerprint") triggers `Kora.callback.trigger('kora_police:server:getFingerprint', targetServerId)` and shows the result via a local notification; the legacy `police:client:showFingerprint`/`showFingerprintId` events do the same for the compat event path.
- A fingerprint also appears as evidence-sample metadata: a collected `fingerprint`-type legacy world-evidence marker is packaged into a `filled_evidence_bag` item whose `info.fingerprint` is `Police.getFingerprint(marker.ownerId)` — so the same deterministic id that search reveals is what ends up on a bagged print.

## Evidence: two mechanisms, not one

- Two independent mechanisms share the name "evidence", and they do not talk to each other:
- 1. **The evidence locker** — a single kora_inventory STASH (`RegisterStash`, `Config.evidence.lockerStashId`, default `police-evidence`) registered at `CreateThread` and again on every `kora_inventory` `onResourceStart` (a kora_inventory restart wipes its own stash table independent of start order). Gated by `{ [Config.police.job] = Config.evidence.minGradeToAccess }` — grade 1 by default, i.e. every officer. This is where seized items/packaged samples actually get stored; it uses zero new inventory code.
- 2. **Legacy "world evidence" markers** (blood drops, casings, fingerprints) — a deliberately thin in-memory registry (`Police.worldEvidence`, id → `{ type, coords, ownerId, bucket, createdAt, expiresAt }`), kept only so the stock `evidence:server:Create*`/`evidence:server:Add*ToInventory`/`evidence:server:Clear*` event names still behave sanely for a third-party script. It is not a CSI minigame: creating a marker is rate-limited per player (`Config.evidence.createCooldown`, 250ms) and capped globally (`Config.evidence.maxWorldMarkers`, 500 — oldest evicted first); collecting one requires `Police.isPolice`, the same routing bucket, `Config.evidence.collectDistance` (2.5m), and consumes one `Config.evidence.bagItem` (`empty_evidence_bag`) to produce a `filled_evidence_bag` with type-specific metadata (a DNA-style hex label for blood, the deterministic fingerprint id for prints, the case id for ballistic casings).
- **Ballistic casings are the one durable, server-authoritative evidence type.** `Police.createBallisticCasing(src, round)` only runs from the `kora_inventory:server:weaponRoundFired` event — kora_inventory has already server-validated the weapon and consumed the round before this fires, so the client supplies nothing trustworthy. A case id (`CS-<unixtime>-<rand6>-<rand6>`) is minted, a world-evidence marker is created with `ballistic = { caseId, roundId, weaponSerial, weapon, ammoType, lot }`, and a row is inserted into `kora_police_ballistic_casings` — the serial, round id and lot stay server-only; only the collected `filled_evidence_bag` gets a label and case id. `Police.getBallisticCasing(caseId)` (exported as `GetBallisticCasing`) is the one read path for an MDT investigation feature to look up a casing by id; there is no client event that exposes the row.

## Dispatch integration: who raises what, and why panic is two calls

- Police does not implement call presentation, map rendering or the response state machine itself — that is entirely `kora_dispatch`'s job (see the Kora Dispatch page). What lives here is the police-specific wording and the decision that an incident IS a police matter: five fixed alert definitions are registered once at boot with `exports.kora_dispatch:registerPlayerAlert` — `kora_police:backup`, `kora_police:gunfire`, `kora_police:gunfire:suppressed`, `kora_police:vehicle-theft`, `kora_police:melee` — each with its own code, title, message, priority, icon and per-type cooldown pulled from `Config.dispatch`.
- **Automatic detection** (`client/detectors.lua`) polls every 500ms for shooting (`IsPedShooting`), vehicle theft/jacking attempts and melee combat, and reports the incident key to `kora_police:server:crimeDetected` — never a priority, service or coordinate, which the server-side registration alone supplies. On-duty officers are excluded from every detector (so a firearms unit returning fire never calls itself in). Detectors are throttled, not debounced, so an ongoing incident reports immediately rather than waiting for it to stop.
- **`/backup`** (client command) calls `kora_police:server:requestBackup`, which requires `Police.isLeo` and raises `kora_police:backup` through `exports.kora_dispatch:createPlayerCall`.
- **The panic button** (`F10` by default, `Config.dispatch.panicKey`) raises TWO separate calls — one to the LEO service (`10-99 Officer Down`, priority 1) and a second, independent one to `Config.police.emsJobType` (default `ems`, `10-52`, priority 1) — because police and EMS keep separate feeds and histories; bundling them would force one shared feed neither service could clear independently. Both calls read the officer's position server-side from their own ped. A 60-second-default cooldown (`Config.dispatch.panicCooldown`) stops one mashed key-press from filling both feeds with duplicates of the same incident; going off duty clears the cooldown immediately (a new shift is a new emergency).
- **Cop-count broadcasting**: `Police.broadcastCopCount()` fires on duty/job changes and pushes the on-duty LEO count (by job TYPE) to `kora_police:client:updateCopCount`, the legacy `police:client:UpdateCurrentCops`/`police:client:SetCopCount` events to on-duty officers, and a bare `police:SetCopCount` broadcast to literally everyone (heist/robbery scripts read this; the count itself is not considered secret).

## The grade-gated armory

- Each armory room is its own `kora_inventory` SHOP (`exports.kora_inventory:RegisterShop`), not a single shared armory with per-item gates — this is explicitly new work (neither qb-policejob's `Config.ArmoryWhitelist` nor qbx_police ships a maintained one). Grade gating happens at the ROOM level: an officer below a shop's `minGrade` cannot even open it, let alone see cheaper items inside.
- Free-issue kit (`price = 0` rows, e.g. the Patrol Armory's stun gun, nightstick, handcuffs, pistol ammo, armor and evidence bags) and chargeable upgrades (Sergeant/SWAT armories' weapons and rifle/shotgun ammo) live in the same shop; `price` alone decides which is which.
- `Config.armory.restockOnStart` (default true) restocks every configured row that is missing or under-amount from kora_inventory's own saved stock, but only once per resource start and only after kora_inventory has finished loading its SAVED shops (`kora_inventory:server:ready` / `getPersistenceStatus().ready`) — restocking before that load completes would just be overwritten by it. A later kora_inventory restart mid-session does not restock again: what was taken that session stays taken.

## Cuffing: soft vs. hard, and the escape minigame

- A **hard cuff** (any on-duty officer's `Cuff` target option or `police:server:CuffPlayer`) cannot be escaped — only an officer's uncuff, `Police.jailPlayer` (silent release on booking), or an admin-equivalent clears it.
- A **soft cuff** comes from the `handcuffs` useable item and is usable by ANYONE, not just police — it resolves the target as the single other player within `Config.cuff.distance` (refusing with "too many people nearby" if more than one qualifies). A soft-cuffed target can attempt `/breakcuffs`: the server issues a one-use `Kora.minigames` proof (`Config.minigames.breakCuffs`, a ported qbx_police-style mash minigame whose difficulty escalates medium→hard→medium over `Config.cuff.breakCuffsAttempts` tries, each gated by `Config.cuff.breakCuffsCooldown` on failure), and only a server-validated winning proof actually releases the cuff.
- An officer's cuff always UPGRADES a soft one to hard (never the reverse); `Config.cuff.recuffRefreshes` (default true) lets re-cuffing an already-restrained target simply refresh the visuals/state instead of refusing with "already cuffed".
- The restraint itself is tracked server-side only (`exports.kora_core:setMetaData(target, 'ishandcuffed', ...)`, mirrored to a replicated player state bag `koraCuffed`/`koraCuffedSoft`) — a client can write its own bag, but an `AddStateBagChangeHandler` immediately puts it back to whatever the server holds for the session. `Config.cuff.restoreOnLogin` (default false) decides whether a stored-but-session-less cuff survives a relog as an anti-combat-log measure; by default a cuff only lasts the session it was put on in.

## Escort, drag and vehicle transfer

Escort requires the suspect to already be cuffed and only an on-duty officer may start/stop it; drag (kidnap-style) works on ANY incapacitated target (cuffed or downed, per `Config.incapacitated`) and anyone may start/stop it — including the dragged player themself once they recover. Neither relationship can coexist with the other on the same target, and both auto-release server-side (a sweep thread, `Config.drag.checkInterval`/no fixed equivalent for escort distance) when the parties separate, enter a vehicle, or the target recovers.

- Attachment is client-side on PURPOSE: each side's own client calls `AttachEntityToEntity`/`DetachEntity` on itself, driven by a server relay — a client cannot be made to move another player's networked ped remotely.
- `Put in vehicle` / `Take out vehicle` require the target to be cuffed and in range; the officer's client supplies a vehicle network id (not a bare "nearest vehicle", except through the legacy compat path which resolves one within 5m).

## Search, seizure and robbery — distinct mechanisms

- **Search** (`Police.search`) only opens the OFFICER'S client UI onto the target's inventory as a secondary session, via kora_inventory's `registerInspectionAccess` policy hook — the officer must be on duty and the target must be cuffed; there is no separate "found items" roll, it is the real inventory.
- **SeizeCash / SeizeDriverLicense** are narrow legacy actions: seize-cash transfers 100% of the target's cash account to the officer in one call; seize-license flips a `licences.driver` metadata flag to `false`. Both require the target cuffed and in range.
- **Rob** (`Police.rob`, `/rob` via `kora_police:server:rob`) is the ONE mechanism open to non-officers: it requires the target incapacitated (cuffed or downed), caps stolen cash at 5× the largest `Config.fine.tiers` value, enforces a per-TARGET cash cooldown (`Config.rob.robCooldownSeconds`, default 300s, so alternating robbers or cuff/uncuff cycles can't double-dip) independent of inventory access, and can additionally grant the robber a time-limited (`Config.rob.accessSeconds`, default 120s) secondary-inventory session on the same inspection-access seam search uses.
