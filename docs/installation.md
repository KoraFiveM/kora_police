---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Police is the LEO job resource: duty/fleet, cuffing/escort/drag, search & seizure, an evidence locker plus legacy "world evidence" markers and durable ballistic casings, a deterministic suspect fingerprint id, a grade-gated armory, citations/jail/impound, spike strips/road props, plate flags (with optional kora_mdt BOLO mirroring), and the police-specific wiring into kora_dispatch. It still answers to the legacy resource names `kora_police` and `qb-policejob`.

## Install Kora Police

1. **Add the folder** — Place `kora_police` in your resources directory (on the Kora recipe it is `resources/[kora]/kora_police`). `provide 'qb-policejob'` is declared, so `exports['qb-policejob']` callers still resolve to it.

2. **Start its dependencies first** — It declares `dependency` on `kora_lib`, `kora_sql`, `kora_core`, `kora_dispatch`, `kora_inventory` and `kora_target`. All six must be ensured before `kora_police`.

   ```bash title="server.cfg"
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_dispatch
   ensure kora_inventory
   ensure kora_target
   ensure kora_police
   ```

3. **Load order inside the resource** — The manifest's script lists are explicit, never globbed: on the server, `schema.lua`/`migrate.lua` (ballistic-casing table) and `core.lua` (the shared `Police` table) load first, `compat/police.lua` loads last because it forwards nearly every legacy event into functions the earlier files define. On the client, `core.lua` loads first (shared state + target helpers) and `compat.lua` loads last.

   ```lua title="fxmanifest.lua" {27,30,31}
   fx_version 'cerulean'
   game 'gta5'
   lua54 'yes'

   name 'kora_police'
   provide 'qb-policejob'    -- second legacy alias

   dependency 'kora_lib'
   dependency 'kora_sql'
   dependency 'kora_core'
   dependency 'kora_dispatch'
   dependency 'kora_inventory'
   dependency 'kora_target'

   shared_scripts {
       '@kora_lib/init.lua',
       'config.lua',
   }

   -- Explicit, non-globbed order: core.lua defines the shared Police table and
   -- must load first; compat/police.lua calls into nearly every other file's
   -- Police.* functions and must load last.
   server_scripts {
       '@kora_sql/init.lua',
       'server/schema.lua', 'server/migrate.lua', 'server/core.lua', 'server/items.lua',
       'server/cuff.lua', 'server/escort.lua', 'server/seize.lua', 'server/bill.lua', 'server/rob.lua',
       'server/jail.lua', 'server/dispatch.lua', 'server/evidence.lua', 'server/armory.lua',
       'server/armour.lua', 'server/fingerprint.lua', 'server/tracker.lua', 'server/impound.lua',
       'server/plate_flag.lua', 'server/duty.lua', 'server/spikes.lua', 'server/objects.lua',
       'server/callbacks.lua', 'server/compat/stash.lua', 'server/compat/police.lua',
   }

   client_scripts {
       'client/core.lua', 'client/cuff_prop.lua', 'client/cuff.lua', 'client/cuff_escape.lua',
       'client/escort.lua', 'client/vehicle.lua', 'client/search.lua', 'client/seize.lua', 'client/rob.lua',
       'client/jail.lua', 'client/bill.lua', 'client/dispatch.lua', 'client/detectors.lua',
       'client/evidence.lua', 'client/spikes.lua', 'client/objects.lua', 'client/camera.lua',
       'client/breach_minigame.lua', 'client/armory.lua', 'client/armour.lua', 'client/fingerprint.lua',
       'client/tracker.lua', 'client/plate_flag.lua', 'client/duty.lua', 'client/impound.lua',
       'client/compat.lua',
   }
   ```

4. **Optional: kora_ambulance** — Downed-state checks (`Police.isDowned`, used by rob/drag incapacitation) read `kora_ambulance`'s `emsDown` state bag and `getPatientStatus` export when that resource is running; without it, only legacy `isdead`/`inlaststand` metadata (and, if `Config.incapacitated.pedHealthFallback` is on, raw ped health) decide whether a target is downed.

5. **Optional: kora_mdt** — Flagging a plate also writes an active vehicle BOLO into `kora_mdt_bolos` when `Config.plateFlags.mirrorToMdt` is on (default true) and `kora_mdt` is started; otherwise the flag stays in this resource's own in-memory registry only.

## Database schema

One table, created by `Kora.sql.ensureTables` in `server/migrate.lua` before anything else touches it.

- `kora_police_ballistic_casings` — one row per server-owned fired round that left a collectible casing: `case_id` (primary key), `round_id`, `weapon_serial`, `weapon_name`, `ammo_type`, `lot`, `x`/`y`/`z`, `bucket` (routing bucket), `created_at`, `collected_by`/`collected_at` (nullable, filled when an officer bags the casing). Indexed on `weapon_serial` and `collected_at`. Everything here is server-only; a client never sees a serial or a round id, only a marker type and coordinates.

## Items this resource registers

`server/items.lua` registers its own catalog via `exports.kora_core:registerShared('items', ...)` at boot rather than editing kora_core's seed file directly, so kora_core's own item list stays job-resource-agnostic.

- `handcuffs` — useable by anyone, soft-cuffs the single other player within `Config.cuff.distance` (see `Police.softCuffNearby`).
- `moneybag` — useable, deposits its `info.amount` into the user's own cash.
- `armor` — useable, applies `Config.armour.items.armor` (50 armour by default); `armour` and `heavyarmor` are usable aliases/extras configured the same way in `Config.armour.items` but not registered as items here (expected to already exist, e.g. from kora_inventory's own catalog).
- `empty_evidence_bag` (`Config.evidence.bagItem`) and `filled_evidence_bag` are consumed/produced by evidence collection but are not registered by this file — they must exist in the item catalog already (the Patrol Armory stocks `empty_evidence_bag` free by default).

## Dependency usage

| Resource | Used for |
| --- | --- |
| `kora_lib` | Shared init (`Kora.*`): notifications, callbacks, events, keybinds, blips, progress bars, minigames, commands, input dialogs |
| `kora_sql` | Table creation and ballistic casing rows (`@kora_sql/init.lua` is loaded on the server) |
| `kora_core` | Player data, jobs and duty, metadata, money, items and useables, garage and jail exports |
| `kora_dispatch` | Police, backup, panic and detector calls (`createCall`, `createPlayerCall`, `registerPlayerAlert`, `setTheme`) |
| `kora_inventory` | Shops, stashes, inspection access, `AddItem` / `RemoveItem`, weapon-fired event |
| `kora_target` | Every interaction option and zone on the client |

## Optional resources

Used only when started and not declared in the manifest:

| Resource | Used for |
| --- | --- |
| `kora_ambulance` | Downed state (`emsDown` state bag and `getPatientStatus`) for rob and drag |
| `kora_mdt` | Plate flags are mirrored into its `kora_mdt_bolos` table (`Config.plateFlags.mirrorToMdt`) |
| `kora_phone` | Closed when a player is cuffed (`Config.cuff.closePhone`) |

## First-run setup

1. No SQL import is needed. On start the resource creates its table through `Kora.sql.ensureTables` (see [Database](./database.md)).
2. Items: `handcuffs`, `moneybag` and `armor` are registered by this resource at start. The evidence bag items and the other armory items must exist in the `kora_core` shared items (see [Items](./items.md)).
3. Make sure a job named `Config.police.job` (default `police`) exists with grade levels 1 and up, and that other law-enforcement jobs use job type `leo` if they should receive calls.
4. Adjust [Configuration](./configuration.md): station, armory, evidence and impound coordinates default to Mission Row.
