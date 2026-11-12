---
title: Configuration
sidebar_position: 7
---

# Configuration

All options are in `config.lua`, a single `Config` table with one sub-table per feature. The table is registered with `kora_lib` (`Kora.config.adopt`), so server owners can override values with the generated `config.local.lua` (git-ignored). Options marked "not read" are present in `config.lua` but no code in this resource reads them.

## `Config.police`

| Key | Default | Meaning |
| --- | --- | --- |
| `job` | `'police'` | Job name gating every department-specific server check |
| `jobType` | `'leo'` | `kora_core` job type that receives dispatch calls, counts as on-duty LEO and may use backup and panic |
| `emsJobType` | `'ems'` | Job type that receives the `10-52` call from the panic button |

## `Config.performance`

`diagnostics` (default `false`): print bounded scan totals when the spike and plate-flag workers stop.

## `Config.cuff`

| Key | Default | Meaning |
| --- | --- | --- |
| `cuffTime` | `5000` | Not read |
| `distance` | `2.5` | Max distance to cuff, uncuff, escort, drag, search, seize, bill, track and put in vehicle; also the target-option range |
| `breakCuffsDifficulty` | `{ 'medium', 'hard', 'medium' }` | Difficulty name per escape attempt (keys of `Config.minigames.breakCuffs.opts`) |
| `breakCuffsAttempts` | `3` | Total escape attempts (failed or successful) per soft cuff |
| `breakCuffsCooldown` | `60000` | ms to wait after a failed attempt |
| `disabledControls` | list of control ids | Controls blocked while cuffed |
| `animCheckInterval` | `500` | ms between cuff-animation checks while cuffed (minimum 250) |
| `recuffRefreshes` | `true` | Cuffing a cuffed player re-applies the restraint; `false` refuses |
| `cufferCanUncuff` | `true` | The player who soft-cuffed someone may release them |
| `uncuffCommand` | `'uncuff'` | Command that releases the nearest cuffed player; `''` for none |
| `restoreOnLogin` | `false` | Bring a stored cuff back at login as a hard cuff |
| `verifyWithServer` | `true` | Client asks the server to confirm a cuff it sees on itself |
| `clearTasksOnUncuff` | `true` | Clear the freed ped's tasks (on foot, not downed) |
| `uncuffRecheckMs` | `1000` | ms after an uncuff to re-check and remove leftovers; `0` is off |
| `blockTargeting` | `true` | Disable the `kora_target` eye while cuffed |
| `holsterWeapon` | `true` | Put the weapon away when cuffed |
| `closePhone` | `true` | Close `kora_phone` when cuffed |
| `notify` | `cuffed`, `uncuffed` texts | Messages sent to the suspect; `''` or `false` for none |
| `anims` | `cuff` and `uncuff`, each with `officer` and `suspect` | Animation dict, clip, duration, flag; the suspect cuff side has an `attach` table (bone, offset, rotation, ms) |
| `prop` | enabled, model `p_cs_cuffs_02_s`, bone `60309` | Handcuff prop on the wrist: `offset`, `rotation`, `checkInterval` (minimum 250) |

## `Config.incapacitated`

`downed` (`true`) and `cuffed` (`true`) say which targets may be robbed or dragged; `ambulance` (`true`) reads `kora_ambulance` state when it is running; `pedHealthFallback` (`false`) treats a ped at or below 100 health as downed.

## `Config.jail`

`defaultMinutes` (`10`): sentence used when none is given, and the default in the booking dialog.

## `Config.evidence`

| Key | Default | Meaning |
| --- | --- | --- |
| `lockerStashId`, `lockerLabel`, `lockerSlots`, `lockerMaxWeight` | `'police-evidence'`, `'Evidence Locker'`, `100`, `200000` | Evidence locker stash |
| `lockerCoords`, `lockerDistance` | `vector4(441.9, -984.5, 30.7, 90.0)`, `2.0` | Where the locker target is |
| `minGradeToAccess` | `1` | Minimum `job.grade.level` for the locker and the stock evidence drawers |
| `clearDistance`, `clearMaxMarkers` | `10.0`, `50` | Limits for stock blood and casing clear requests |
| `statusTtl`, `statuses`, `statusDistance` | `600000`, id-to-label table, `5.0` | Stock player status list (see [Compatibility](./compatibility.md)) |
| `drawers` | `rooms`, `maxDrawer` 20, `distance` 3.0, `slots` 500, `maxWeight` 4000000 | Stock `qb-policejob:server:evidence` drawers |
| `worldMarkerTtl`, `maxWorldMarkers`, `createCooldown`, `collectDistance` | `1800000`, `500`, `250`, `2.5` | World marker lifetime, cap, per-player creation cooldown (ms), collect range |
| `bagItem`, `bagLabel`, `missingBagMessage` | `'empty_evidence_bag'`, `'Empty Evidence Bag'`, message with two `%s` | Bag needed to collect samples |
| `ballistic.enabled`, `ballistic.casingOffset` | `true`, `0.75` | Fired rounds leave casings within this radius of the shooter |
| `ballistic.databaseRetentionDays`, `ballistic.analysis` | `90`, `requiredStages` and `games` | Not read by this resource |

## `Config.armour`

`enabled`, `mode` (`'set'` or `'add'`), `blockIfFull`, `fullMessage`, `progress` (label, duration, canCancel, anim) and `items` (item name to `amount`, optional `mode`, `duration`, `label`, `anim`). Defaults: `armor` 50, `armour` 50, `heavyarmor` 100.

## `Config.armory`

`restockOnStart` (`true`) and `shops`: a list of `{ id, label, coords, distance, minGrade, slots, items }`, where each item is `{ name, price, amount }`. Defaults: `pd-armory-patrol` (grade 1), `pd-armory-sergeant` (grade 3), `pd-armory-swat` (grade 4). Items with `price = 0` are free issue.

## `Config.stash`

Stock stashes: `personal` and `trash` (slots, maxWeight), `clearTrashOnStart` (`true`), `distance` (`5.0`) and `locations` (list of vector3; empty means no distance check).

## `Config.objects`

`types` (cone, barrier, roadsign, tent, light, each with `model` and `freeze`), `placeDistance` (`0.5`), `deleteDistance` (`5.0`), `maxPerOfficer` (`20`), `lifetime` (`1800000`), `cooldown` (`500`).

## Small tables

- `Config.tracker.locationCooldown` (`5000`): ms between tracker location replies per player.
- `Config.heli.spotlightCooldown` (`500`): ms between helicopter spotlight toggles per player.
- `Config.impound`: `fee` (`500`), `maxFee` (`10000`), `takeOutDistance` (`10.0`), `progress` (enabled, duration, label, canCancel, anim, prop) and `lots` (`id`, `label`, `coords`).
- `Config.plateFlags`: `mirrorToMdt` (`true`), `days` (`7`) the MDT BOLO stays active.
- `Config.spikes`: `model`, `lifetime` (`120000`), `maxDeployed` (`6` per officer), `deployDistance` (`5.0`), `deflateDistance` (`1.2`).
- `Config.cameras`: `hideRadar` and `list` (id to `label`, `coords`, `r`, `canRotate`, `isOnline`).
- `Config.breach.doors`: list of `{ id, enabled, model, coords, unlockedFor }`. The demo door is disabled.
- `Config.minigames`: `breach` (`lockpick`, `pinCount`, `attempts`) and `breakCuffs` (`mash` with `easy`, `medium`, `hard` round options).

## `Config.dispatch`

| Key | Default | Meaning |
| --- | --- | --- |
| `accent` | `'#3B82F6'` | Dispatch UI accent for police players |
| `panicKey` | `'F10'` | Default panic keybind (rebindable) |
| `backupCooldown` | `15000` | ms between backup calls per officer |
| `panicCooldown` | `60000` | ms between panic alarms per officer |
| `shotsFiredCooldown`, `vehicleTheftCooldown`, `meleeCooldown` | `20000`, `30000`, `30000` | Detector alert cooldowns |
| `legacyAlertCooldown`, `legacyAlertMaxLength` | `15000`, `120` | Limits for `police:server:policeAlert` |
| `copCountThrottle` | `2000` | ms between legacy cop-count broadcast requests per player |
| `robberyRadius` | `30.0` | Call `radius` default, and default radius for `police:IsPoliceForcePresent` |

## `Config.duty`

`actionCooldown` (`1000`), `vehicleSpawnDistance` (`15.0`), `points` (`coords`, `radius`, `label`, optional `blip`) and `vehicles` (`model`, `label`, `coords`). Fleet plates are `POLICE` plus the two-digit list index, so reordering the list reassigns plates.

## `Config.fine`, `Config.Citations`, `Config.rob`, `Config.drag`

- `Config.fine.tiers` (`{ 100, 3 }`, `{ 250, 2 }`, `{ 500, 1 }`): the first value is the default amount in the citation dialog; the largest value sets the rob cash cap (times five). `account` (`'bank'`) is charged for citations.
- `Config.Citations`: `autoDeduct` (`false`), `maxUnpaid` (`25`), `payMethods.command` and `payMethods.exports` (both `true`), `listCommand` (`'citations'`), `payCommand` (`'paycitation'`).
- `Config.rob`: `takeCash`, `openInventory` (both `true`), `accessSeconds` (`120`), `closeDistance` (`4.0`), `checkInterval` (`1000`), `robCooldownSeconds` (`300`, `0` for none).
- `Config.drag`: `releaseKey` (`'E'`), `releaseCommand` (`'releasedrag'`), `releaseControl` (`0`, optional polled control), `releasePrompt`, `releaseHint`, `autoReleaseDistance` (`8.0`), `releaseInVehicle`, `releaseWhenRecovered`, `checkInterval` (`1000`), `bone`, `offset`, `rotation`.
