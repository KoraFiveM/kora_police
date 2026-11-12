---
title: Installation
sidebar_position: 2
---

# Installation

## Requirements

Declared with `dependency` in `fxmanifest.lua`:

| Resource | Used for |
| --- | --- |
| `kora_lib` | Shared init (`Kora.*`): notifications, callbacks, events, keybinds, blips, progress bars, minigames, commands, input dialogs |
| `kora_sql` | Table creation and ballistic casing rows (`@kora_sql/init.lua` is loaded on the server) |
| `kora_core` | Player data, jobs and duty, metadata, money, items and useables, garage and jail exports |
| `kora_dispatch` | Police, backup, panic and detector calls (`createCall`, `createPlayerCall`, `registerPlayerAlert`, `setTheme`) |
| `kora_inventory` | Shops, stashes, inspection access, `AddItem` / `RemoveItem`, weapon-fired event |
| `kora_target` | Every interaction option and zone on the client |

Optional, used only when started and not declared in the manifest:

| Resource | Used for |
| --- | --- |
| `kora_ambulance` | Downed state (`emsDown` state bag and `getPatientStatus`) for rob and drag |
| `kora_mdt` | Plate flags are mirrored into its `kora_mdt_bolos` table (`Config.plateFlags.mirrorToMdt`) |
| `kora_phone` | Closed when a player is cuffed (`Config.cuff.closePhone`) |

The manifest also declares `provide 'qb-policejob'`, so scripts that depend on `qb-policejob` resolve to this resource.

## Steps

1. Put the resource in your resources folder.
2. Ensure it after its dependencies:

   ```cfg
   ensure kora_sql
   ensure kora_lib
   ensure kora_core
   ensure kora_inventory
   ensure kora_target
   ensure kora_dispatch
   ensure kora_police
   ```

3. No SQL import is needed. On start the resource creates its table through `Kora.sql.ensureTables` (see [Database](./database.md)).
4. Items: `handcuffs`, `moneybag` and `armor` are registered by this resource at start. The evidence bag items and the other armory items must exist in the `kora_core` shared items (see [Items](./items.md)).
5. Make sure a job named `Config.police.job` (default `police`) exists with grade levels 1 and up, and that other law-enforcement jobs use job type `leo` if they should receive calls.
6. Adjust [Configuration](./configuration.md): station, armory, evidence and impound coordinates default to Mission Row.
