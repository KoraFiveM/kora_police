---
title: "Duty, fleet, armory & armour"
sidebar_position: 6
---


# Duty, fleet, armory & armour

Going on/off duty at a configured point, the patrol-fleet register/spawn/store loop (on `Core.garage`), the grade-gated armory shops, and the armour useable-item handlers (vest application with a cancellable progress bar re-validated server-side).

Namespace: `Police.* (server)` · Source: `server/duty.lua, server/armory.lua, server/armour.lua`

## How it works

Armour application is attacker-resistant: the client reports its own progress-bar completion, but the server independently measures elapsed time against the configured duration (±250ms tolerance) and rejects a use that finished implausibly fast.

## Config.duty / Config.armory / Config.armour (config.lua)

Pass an options table as the final argument to a play function. Omit the table or any field to use its default.

| Option | Type | Description |
| --- | --- | --- |
| `duty.points / duty.vehicles / duty.actionCooldown / duty.vehicleSpawnDistance` | table | Duty zones (with optional map blip), the fleet roster, the duty-toggle cooldown (1s), and how far from a fleet point a spawn/store may happen (15m). |
| `armory.restockOnStart / armory.shops[].minGrade` | boolean / integer | Whether missing/short free-issue stock is restored on boot; the grade ladder gating each room (Patrol=1, Sergeant=3, SWAT=4 by default). |
| `armour.enabled / mode / blockIfFull / items` | boolean / string / table | `mode` is `set` (replaces current armour) or `add` (adds, capped at 100), overridable per item; `blockIfFull` refuses a use that would not raise armour. |

## Functions

5 Police.* functions of note.

### `Police.spawnDutyVehicle(src, plate) / Police.storeDutyVehicle(src, plate)`

Spawns or stores a job-fleet vehicle (`Core.garage` row with no citizenid, `job = Config.police.job`). Plates follow `POLICE%02d` and are matched back to their configured spawn point/distance.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer |  |
| `plate` | string |  |

**Returns**

- **networkId / ok, err.**

**Example**

```lua
Police.spawnDutyVehicle(source, 'POLICE01')
```

**Representative console output**

```text
Refuses if not `Police.isPolice`, the plate is not a fleet vehicle, or the caller is too far from the configured garage point (`Config.duty.vehicleSpawnDistance`, 15m).
```

### `Police.canAccessArmory(src, shopId)`

Checks on-duty + grade (`Config.armory.shops[].minGrade`) + distance before a shop is allowed to open. Re-checked independently by kora_inventory's own shop `groups` policy.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer |  |
| `shopId` | string |  |

**Returns**

- **ok, err.**

**Example**

```lua
local ok, err = Police.canAccessArmory(source, 'pd-armory-sergeant')
```

**Representative console output**

```text
`insufficient rank`, `too far away`, `unknown armory`, or `not an on-duty officer`.
```

### `Police.restockArmory(shop)`

Tops up / re-adds configured rows missing from kora_inventory's SAVED shop stock. Runs once per resource start, gated on kora_inventory finishing its own saved-shop load.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `shop` | table | A `Config.armory.shops` entry. |

**Returns**

- **changed** — boolean.

**Example**

```lua
Police.restockArmory(Config.armory.shops[1])
```

**Representative console output**

```text
Never restocks mid-session after a later kora_inventory-only restart.
```

## Limits and related APIs

Fleet vehicles are tracked purely through `Core.garage` rows keyed by the fixed `POLICE%02d` plate pattern — renumbering `Config.duty.vehicles` changes which plate maps to which vehicle.

## Related guides

- [Jail, citations, impound & plate flags](./jail-citations-impound.md)
- [Field tools](./field-tools.md)
