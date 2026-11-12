---
title: "Field tools"
sidebar_position: 8
---


# Field tools

## Server

Ankle trackers, spike strips, road props and the heli spotlight toggle — every one a real networked server-owned entity (or a plain in-memory flag for the tracker), never a client-trusted creation/removal.

Namespace: `Police.* (server)` · Source: `server/tracker.lua, server/spikes.lua, server/objects.lua`

### Config.tracker / Config.spikes / Config.objects / Config.heli

Pass an options table as the final argument to a play function. Omit the table or any field to use its default.

| Option | Type | Description |
| --- | --- | --- |
| `tracker.locationCooldown` | integer | Minimum ms between a tracked player's location replies (5000). |
| `spikes.model / lifetime / maxDeployed / deployDistance / deflateDistance` | string / integer / number | p_ld_stinger_s by default; 120s lifetime; 6 per officer; 5m max placement distance from the officer; 1.2m tyre-pop radius. |
| `objects.types / placeDistance / deleteDistance / maxPerOfficer / lifetime / cooldown` | table / number / integer | Five prop types; placed 0.5m in front of the officer; 20 per officer; 30 min lifetime; 500ms placement cooldown. |
| `heli.spotlightCooldown` | integer | Minimum ms between toggles (500). |

### Functions

9 Police.* functions of note.

#### `Police.setTracker(officerSrc, targetSrc, active) / Police.toggleTracker(officerSrc, targetSrc)`

Attaches/removes a GPS ankle tracker. `setTracker` is the native form; `toggleTracker` mirrors the stock `police:server:SetTracker` toggle, requiring BOTH parties in reach (unlike stock, which lets an officer toggle remotely).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `targetSrc` | integer | The suspect/civilian's server id. |
| `active` | boolean | setTracker only. |

**Returns**

- **ok, err (setTracker); ok, err, active (toggleTracker).**

**Example**

```lua
Police.toggleTracker(source, target)
```

**Representative console output**

```text
Tracked players are pinged every 15s to voluntarily report their position; replies are rate-limited per player by `Config.tracker.locationCooldown` (5s).
```

#### `Police.deploySpike(officerSrc, coords) / Police.removeSpike(netId)`

Creates/removes a REAL networked `CreateObject` spike strip (not a local-only `Kora.entities` spawn, since every player on the road must see it).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `coords` | vector3 |  |

**Returns**

- **netId, err.**

**Example**

```lua
Police.deploySpike(source, coords)
```

**Representative console output**

```text
Capped at `Config.spikes.maxDeployed` (6) per officer; server re-validates the requested position is within `Config.spikes.deployDistance` of the officer, not an arbitrary world point.
```

#### `Police.spawnObject(officerSrc, objectType) / Police.deleteObject(officerSrc, objectId) / Police.deleteNearestObject(officerSrc)`

Road props (cones, barriers, signs, tents, lights — `Config.objects.types`), server-created and server-deleted (stock lets any client create/delete any prop).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `objectType` | string |  |

**Returns**

- **id, err.**

**Example**

```lua
Police.spawnObject(source, 'cone')
```

**Representative console output**

```text
Capped at `Config.objects.maxPerOfficer` (20) with a per-placement cooldown (`Config.objects.cooldown`, 500ms); props auto-expire after `Config.objects.lifetime` (30 min).
```

#### `Police.setHeliSpotlight(src, state)`

Toggles a helicopter spotlight. Requires `Police.isLeo` and the caller actually seated in the pilot/co-pilot seat of a heli.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer |  |
| `state` | boolean |  |

**Returns**

- **boolean.**

**Example**

```lua
Police.setHeliSpotlight(source, true)
```

**Representative console output**

```text
Rate-limited by `Config.heli.spotlightCooldown` (500ms).
```

### Limits and related APIs

Spike strips and props are world-visible to everyone, not just police, since they are real networked entities on the road.

### Related guides

- [Duty, fleet, armory & armour](./duty-fleet-armory.md)

## Client

Spike-strip tyre-deflate proximity checks (only polled while this player is in a vehicle AND a strip exists — no idle on-foot loop); road-prop placement/removal targets; a purely local security-camera viewer (`Config.cameras.list`, stock `police:client:ActiveCamera`); the door-breach lockpick minigame (a genuine FiveM door-system lock, no server round trip for the lock state itself); and a lightweight ALPR-style plate scan while on duty and driving, which calls `kora_police:server:flagPlate`/`unflagPlate`/`plateSpotted`.

Namespace: `Police.* (server)` · Source: `client/tracker.lua, client/spikes.lua, client/objects.lua, client/camera.lua, client/breach_minigame.lua, client/plate_flag.lua`

### Functions

No client exports.
