---
title: Player interactions
sidebar_position: 8
---

# Player interactions

The resource has no NUI of its own. Everything is a `kora_target` option, a `kora_lib` input dialog or progress bar, a blip or a notification. Options are removed and re-registered when `kora_target` restarts.

## Target options on players

Range is `Config.cuff.distance`.

| Option | Shown when | Result |
| --- | --- | --- |
| Cuff | On duty, target not cuffed | `kora_police:server:cuff` |
| Uncuff | On duty, target cuffed | `kora_police:server:uncuff` |
| Escort | On duty, target cuffed, you are not escorting | Starts an escort |
| Stop Escorting | Looking at your escorted target | Ends the escort |
| Drag | You are not dragging, target cuffed or downed (per `Config.incapacitated`) | Starts a drag |
| Release | You are dragging; offered on players, peds and vehicles | Releases the drag |
| Search | On duty, target cuffed | Opens their inventory |
| Seize Cash, Seize Driver's License | On duty, target cuffed | Seizure events |
| Rob | You are not on duty, target cuffed or downed | Rob flow |
| Issue Citation | On duty | Dialog with amount and reason |
| Book (Jail) | On duty, target cuffed | Dialog with minutes and reason |
| Check Fingerprint | On duty, target cuffed | Notification with the fingerprint id |
| Attach Tracker | On duty, target cuffed | Attaches a tracker (see [Features](./features.md)) |

## Target options on vehicles

Put Suspect In Vehicle (while escorting or dragging), Impound Vehicle (on duty), Flag Plate and Unflag Plate (on duty), and Store Patrol Vehicle (on duty and in the driver seat).

## Zones

- Duty points (`Config.duty.points`): an option with the point's `label` for players whose job is `Config.police.job`, plus a station blip when `blip.enabled`.
- Fleet spots (`Config.duty.vehicles`): **Take Out ...** for on-duty officers.
- Armory rooms (`Config.armory.shops`): the shop label, for on-duty officers of at least `minGrade`.
- Evidence locker: opens the stash for the configured grade.
- Impound lots (`Config.impound.lots`): **Retrieve From ...** with a plate dialog, for anyone.
- Evidence markers: on-duty officers get a blip and a **Collect ... evidence** option within 2 m.
- Breach doors (`Config.breach.doors`): **Breach Door** for on-duty officers, if the door is enabled.

## Other UI

- Tracked targets and tracker pings show as blips under "Vehicle Tracking".
- Calls, feed and map belong to `kora_dispatch`; this resource only sets its accent colour (`Config.dispatch.accent`).
- Impounding, armour and road-prop placement use cancellable progress bars.
