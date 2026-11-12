---
title: "MDT readiness & legacy compatibility"
sidebar_position: 9
---


# MDT readiness & legacy compatibility

Two things in one place because they share a checklist: (1) an "MDT-readiness" surface of stock-named callbacks (`police:GetDutyPlayers`, `police:GetCops`, etc.) a future MDT resource can consume with no rework, and (2) the FULL legacy `police:server:*`/`police:client:*`/`evidence:server:*`/`qb-policejob:server:*` event surface, each one forwarding into the same `Police.*` functions the native kora_police flow uses — so a modified or third-party client gains nothing by calling the old name instead of the new one.

Namespace: `Kora.callback / RegisterNetEvent (server)` · Source: `server/callbacks.lua, server/compat/police.lua, server/compat/stash.lua`

## How it works

Every compat handler re-derives its own server-side truth rather than trusting what the legacy payload claims: `police:server:SetHandcuffStatus` with a bare boolean just re-sends the AUTHORITATIVE cuff state rather than accepting the client's claim; `police:server:policeAlert` reads position from the caller's own ped and de-duplicates against kora_core's own `kora_core:server:dispatchAlert` mirror so the same alert cannot double up through two different compat paths; `police:server:spawnObject` disambiguates a road-prop type name from a spike-strip coordinate table by argument type; `police:server:SyncSpikes` only accepts a REMOVAL of a strip this resource's own registry still tracks, by the officer who owns it.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| MDT-readiness | Deliberately UI-less: these callbacks exist so a dedicated MDT resource (e.g. kora_mdt) can be built against a stable surface without this resource needing rework later. |
| Dispatch mirror de-duplication | A 1-second window (`MIRROR_WINDOW_MS`) during which a `police:server:policeAlert` carrying the exact text kora_core already mirrored via `kora_core:server:dispatchAlert` is recognized and dropped, so one alert cannot raise two calls. |

## Functions

7 MDT-readiness Kora.callback registrations of note, plus roughly 30 legacy net-event forwards covering cuff/search/seize/escort/drag/vehicle/bill/jail/rob/tracker/plate-flag/impound/object/spike/fingerprint actions, and the stock `qb-policejob:server:stash`/`trash`/`evidence` drawer events (compat/stash.lua).

### `Kora.callback.trigger('police:GetDutyPlayers')`

The on-duty LEO roster, open to any caller in the stock `{ source, label = callsign, job }` shape; a POLICE caller additionally gets `citizenid`, `name` and `grade`.

**Parameters**



**Returns**

- **table[].**

**Example**

```lua
local roster = Kora.callback.trigger('police:GetDutyPlayers')
```

**Representative console output**

```text
Richer identity fields are withheld from a non-police caller, not merely hidden client-side.
```

### `Kora.callback.trigger('police:GetCops') / Kora.callback.trigger('kora_police:server:getCops')`

The stock form returns a bare on-duty LEO count to ANY caller (heist scripts gate on it); the kora form returns the actual source list, police-only.

**Parameters**



**Returns**

- **integer (GetCops); integer[] (getCops, empty for a non-officer).**

**Example**

```lua
local count = Kora.callback.trigger('police:GetCops')
```

**Representative console output**

```text
Counts by job TYPE, matching the cop-count broadcast.
```

### `Kora.callback.trigger('police:isPlayerDead', target?)`

A non-officer may only ask about themself or someone within `Config.cuff.distance`; an officer may ask about anyone.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `target?` | integer | Defaults to the caller. |

**Returns**

- **boolean.**

**Example**

```lua
Kora.callback.trigger('police:isPlayerDead')
```

**Representative console output**

```text
Checked via `Police.isDowned` first, falling back to legacy `isdead` metadata, then raw ped health.
```

### `Kora.callback.trigger('police:IsSilencedWeapon', weaponOrTarget?)`

Whether the resolved target's EQUIPPED weapon (per kora_inventory, not merely the selected GTA weapon) carries a suppressor component. A non-police caller may only ask about themself.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `weaponOrTarget?` | string\|integer |  |

**Returns**

- **boolean.**

**Example**

```lua
Kora.callback.trigger('police:IsSilencedWeapon')
```

**Representative console output**

```text
The inventory is authoritative: the selected weapon must match the equipped one before any suppressor check runs.
```

### `Kora.callback.trigger('police:IsPoliceForcePresent', coords?, radius?) / Kora.callback.trigger('police:server:IsPoliceForcePresent')`

The coords form (police-only caller) checks any on-duty officer within radius of a point; the argument-less stock form checks for ANY on-duty grade-2+ (Officer+) LEO anywhere on the server.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords?` | vector3 |  |
| `radius?` | number | Default `Config.dispatch.robberyRadius`. |

**Returns**

- **boolean.**

**Example**

```lua
Kora.callback.trigger('police:server:IsPoliceForcePresent')
```

**Representative console output**

```text
Unlike stock, requires on-duty — an off-duty chief never suppresses a heist.
```

### `Kora.callback.trigger('police:GetPlayerStatus', target?) / Kora.callback.trigger('kora_police:server:getPlayerStatus', target?)`

Stock form: police-only, in-reach, returns only status labels (drunk/gunpowder/etc. from `evidence:server:UpdateStatus`). Kora form additionally returns citizenid, job, cuffed/tracked/escorted/dragged state.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `target?` | integer |  |

**Returns**

- **string[] (GetPlayerStatus); table|nil (getPlayerStatus).**

**Example**

```lua
Kora.callback.trigger('kora_police:server:getPlayerStatus', target)
```

**Representative console output**

```text
Status labels are server-controlled (`Config.evidence.statuses`) — a client can only set IDS it recognizes, never arbitrary text.
```

### `Kora.callback.trigger('police:GetImpoundedVehicles') / Kora.callback.trigger('police:IsPlateFlagged', plate)`

Police-only reads of this resource's impound index and plate-flag registry.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `plate` | string | IsPlateFlagged only. |

**Returns**

- **table[] (GetImpoundedVehicles); flagged, entry (IsPlateFlagged).**

**Example**

```lua
local flagged = Kora.callback.trigger('police:IsPlateFlagged', plate)
```

**Representative console output**

```text
Both refuse with an empty/false result for a non-officer caller.
```

## Limits and related APIs

This is a compatibility and read surface — every mutating legacy event still runs through the identical permission checks documented in the function module that owns the underlying `Police.*` call (cuff, escort, seize, bill, jail, tracker, plate flag, spikes/objects).

## Related guides

- [Restraint, escort & transport](./restraint-escort-transport.md)
- [Jail, citations, impound & plate flags](./jail-citations-impound.md)
- [Dispatch & crime detection](./dispatch-crime-detection.md)
