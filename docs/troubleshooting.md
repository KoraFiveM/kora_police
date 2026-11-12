---
title: Troubleshooting
sidebar_position: 14
---

# Troubleshooting

## Nothing happens on a target option

The server refuses silently only for actions that ignore a bad caller. Most refusals notify the caller with the reason (for example "not an on-duty officer" or "too far away"). Check duty, grade and distance first. Distances use `Config.cuff.distance` (2.5 m by default).

## Cannot cuff / search / seize

The target must be within range, and search, seize, escort and fingerprint need a cuffed target. Cuffing needs you to be police and on duty and not cuffed yourself.

## Cuffs come back (or vanish) after relog

A cuff only lasts for the session it was applied in. Set `Config.cuff.restoreOnLogin = true` to keep a cuff through logout and disconnect.

## Cannot collect evidence

Collecting needs an on-duty police player within `Config.evidence.collectDistance`. Ballistic casings and the stock `evidence:server:Add*ToInventory` events also need an `empty_evidence_bag` (the Patrol Armory issues them).

## Armory or evidence locker does nothing

Check that `kora_inventory` is started, the shop `minGrade` matches your grade levels (grades start at 1), and the shop items exist. After a `kora_inventory` restart this resource re-registers shops and the locker, but a restock only runs when this resource starts.

## No dispatch calls

`kora_dispatch` must be running. Recipients are on-duty players whose job type is `Config.police.jobType`. Backup and panic need that job type and duty.

## Plate flags missing after restart

Flags are in memory only. The `kora_mdt` BOLO, when mirrored, stays and can still be resolved with **Unflag Plate**.

## Breach door shows no option

The demo door in `Config.breach.doors` is disabled by default because it overlaps the Patrol Armory.

## Known caveats

- `Config.cuff.cuffTime`, `Config.evidence.ballistic.databaseRetentionDays` and `Config.evidence.ballistic.analysis` are not read.
- The impound lot option label shows `Config.impound.fee`, but the fee charged is the one stored when the vehicle was impounded.
- The `tests/` feature file is a converted legacy checklist; review it before relying on it.
