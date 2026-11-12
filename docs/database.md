---
title: Database
sidebar_position: 13
---

# Database

## Table created by this resource

`server/schema.lua` and `server/migrate.lua` create the table with `Kora.sql.ensureTables` after waiting up to 60 seconds for `kora_sql`. If `kora_sql` is unavailable, ballistic evidence is disabled until restart (an error is printed).

`kora_police_ballistic_casings` (one row per casing):

| Column | Type | Notes |
| --- | --- | --- |
| `case_id` | `varchar(64)` | Primary key, format `CS-time-random-random` |
| `round_id` | `varchar(96)` | Round id from `kora_inventory` |
| `weapon_serial` | `varchar(96)` | Never sent to clients |
| `weapon_name` | `varchar(96)` | |
| `ammo_type`, `lot` | `varchar(64)`, nullable | |
| `x`, `y`, `z` | `double` | Casing position |
| `bucket` | `int` | Routing bucket, default 0 |
| `created_at` | `timestamp` | Default current time |
| `collected_by` | `varchar(64)`, nullable | Citizen id of the collecting officer |
| `collected_at` | `timestamp`, nullable | |

Indexes: `idx_ballistic_serial` (`weapon_serial`) and `idx_ballistic_collected` (`collected_at`). Nothing in this resource deletes rows; `Config.evidence.ballistic.databaseRetentionDays` is not read, so cleanup is up to the server owner.

## Tables used through other resources

- `kora_mdt_bolos` (owned by `kora_mdt`): on flag, an active `vehicle` BOLO is inserted, or the existing one updated; on unflag, active ones are set to `resolved`. Skipped unless `kora_mdt` is started and `Config.plateFlags.mirrorToMdt` is not `false`.
- The garage (`player_vehicles` rows through `kora_core`): fleet vehicles are created with plates `POLICE01` and up and job `Config.police.job`; impound state is set through `kora_core`.
- `kora_inventory` persistence stores shop and stash contents.

## Player metadata (via `kora_core`)

| Key | Written by | Meaning |
| --- | --- | --- |
| `ishandcuffed` | cuff and release | Cuff flag; see [Features](./features.md) for login handling |
| `citations` | citations | Unpaid citation list |
| `licences` | seize licence | `driver` set to `false` |
| `tracker` | tracker | Tracker flag |

Plate flags, fingerprints, world evidence markers, escort and drag state, and impounded-plate lists are in memory only and are lost on restart.
