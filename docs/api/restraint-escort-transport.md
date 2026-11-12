---
title: "Restraint, escort & transport"
sidebar_position: 2
---


# Restraint, escort & transport

## Server

Every way a suspect is physically controlled: cuffing (hard and soft), the skillcheck escape for a soft cuff, escort (walking a cuffed suspect), drag (kidnap-style movement of any incapacitated target), and vehicle seating.

Namespace: `Police.* (server), net events kora_police:server:*` · Source: `server/cuff.lua, server/escort.lua`

### How it works

The restraint itself lives in `exports.kora_core:setMetaData(target, 'ishandcuffed', ...)`, mirrored to a replicated `koraCuffed`/`koraCuffedSoft` player state bag. `Police.cuffState[src]` (in-memory: `{ soft, officer, cuffer, attemptsUsed, cooldownUntil }`) is the session-scoped source of truth; a cuff only persists for the session it was applied in unless `Config.cuff.restoreOnLogin` is true. A `kora_core:server:playerLoaded`/`onResourceStart` sync reconciles the metadata, the live session table and the state bag on login and on this resource's own restart so none of the three can disagree.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Hard vs. soft cuff | Hard = applied by an on-duty officer, cannot be escaped. Soft = applied via the `handcuffs` item by anyone, escapable with /breakcuffs. An officer's cuff always upgrades a soft one. |
| koraCuffed / koraCuffedSoft | Replicated player state bag keys. Server-authoritative: any client write is detected via `AddStateBagChangeHandler` and overwritten back to the session value. |

### Functions

9 Police.* functions plus 7 net events (kora_police:server:cuff/uncuff/breakCuffsResult/escort/deEscort/startDrag/stopDrag/putInVehicle/takeOutVehicle) and 2 Kora.callback registrations (beginBreakCuffs, getCuffed).

#### `Police.cuff(officerSrc, targetSrc)`

Hard-cuffs a target. Refuses self-cuffing, a restrained officer, an unreachable target, or (unless `Config.cuff.recuffRefreshes`) an already-cuffed one.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `targetSrc` | integer | The suspect/civilian's server id. |

**Returns**

- **ok** — boolean.
- **err** — one of `not an on-duty officer`, `cannot cuff yourself`, `you are restrained`, `target not found`, `already cuffed`, `too far away` (see `Police.cuffRefusal` for the player-facing wording).
- **info** — `refreshed` when an already-cuffed target's restraint was re-applied.

**Example**

```lua
RegisterNetEvent('kora_police:server:cuff', function(target)
    local ok, err, info = Police.cuff(source, tonumber(target))
end)
```

**Representative console output**

```text
Called by the client's "Cuff" kora_target option on a player, or the legacy `police:server:CuffPlayer` event.
```

#### `Police.uncuff(requesterSrc, targetSrc, opts?)`

Releases a cuff. Self-release only works on a SOFT cuff (an escape, not an uncuff); an officer or the original soft-cuffer (if `Config.cuff.cufferCanUncuff`) may release anyone in range.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `requesterSrc` | integer |  |
| `targetSrc` | integer | The suspect/civilian's server id. |
| `opts?` | &#123; silent?: boolean &#125; | `silent` suppresses the uncuff animation/notification — used by `Police.jailPlayer` on booking. |

**Returns**

- **ok** — boolean.
- **err** — `not cuffed`, `not authorised`, `cannot self-release a hard cuff`, `too far away`.

**Example**

```lua
local ok, err = Police.uncuff(source, target)
```

**Representative console output**

```text
A client that believes itself cuffed but has no live server state is corrected (freed) rather than left to disagree with the server.
```

#### `Police.softCuffNearby(src)`

The `handcuffs` useable item's handler: soft-cuffs the single other player within `Config.cuff.distance`. Usable by ANY player, not just police.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer |  |

**Returns**

- **ok** — boolean.
- **err** — `handcuffs required`, `no one nearby to cuff`, `too many people nearby -- move closer to just one target`, `already cuffed` (if nobody uncuffed is in reach and recuffRefreshes is off).
- **info** — `refreshed`.

**Example**

```lua
exports.kora_core:createUseable('handcuffs', function(src) return Police.softCuffNearby(src) end)
```

**Representative console output**

```text
Registered as the item's useable handler; not called directly by other code.
```

#### `Kora.callback.trigger('kora_police:server:beginBreakCuffs')  then  TriggerServerEvent('kora_police:server:breakCuffsResult', proof)`

The two-step escape flow for a soft cuff: the server authorizes a one-use `Kora.minigames` proof scaled to the current attempt's difficulty (`Config.cuff.breakCuffsDifficulty`), the client plays `Config.minigames.breakCuffs` (a mash minigame), and the result proof is sent back for server-side validation before the cuff is actually released.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer |  |

**Returns**

- **beginBreakCuffs: authorization** — opaque string, or nil + an error (`not soft-cuffed`, `attempt already in progress`, `on cooldown`, `no attempts remaining`, `could not authorize escape attempt`).
- **breakCuffsResult has no return; it notifies the player directly.**

**Example**

```lua
local authorization, err = Kora.callback.trigger('kora_police:server:beginBreakCuffs')
if authorization then
    local result = Kora.minigames.play(Config.minigames.breakCuffs.type, nil, authorization)
    TriggerServerEvent('kora_police:server:breakCuffsResult', result.success and result.proof or false)
end
```

**Representative console output**

```text
A failed/cancelled attempt consumes one of `Config.cuff.breakCuffsAttempts` and starts `Config.cuff.breakCuffsCooldown` (60s).
```

#### `Police.escort(officerSrc, targetSrc) / Police.deEscort(requesterSrc, targetSrc)`

Attaches a CUFFED suspect to an officer's ped, client-side on each party's own client, driven by this server relay. Only one of escort/drag may apply to a target at once.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `targetSrc` | integer | The suspect/civilian's server id. |

**Returns**

- **ok** — boolean.
- **err** — `not an on-duty officer`, `target is not cuffed`, `already being escorted`, `target is being dragged`, `too far away` (escort); `not being escorted`, `not authorised` (deEscort).

**Example**

```lua
Police.escort(source, target)
```

**Representative console output**

```text
deEscort may be called by the officer or by the escorted player themself (e.g. breaking free clears it via `Police.uncuff`).
```

#### `Police.startDrag(draggerSrc, targetSrc) / Police.stopDrag(requesterSrc, targetSrc)`

Drag (kidnap-style) ANY incapacitated target — cuffed or downed, per `Config.incapacitated`. Unlike escort, the dragger does NOT need to be police.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `draggerSrc` | integer |  |
| `targetSrc` | integer | The suspect/civilian's server id. |

**Returns**

- **ok** — boolean.
- **err** — `cannot drag yourself`, `you are restrained` (dragger is cuffed), `target not found`, `already being dragged`, `target is being escorted`, `too far away`, `target is not restrained or down`.

**Example**

```lua
Police.startDrag(source, target)
```

**Representative console output**

```text
A sweep thread (`Police.sweepDrags`, interval `Config.drag.checkInterval`) auto-releases a drag when the pair separates past `Config.drag.autoReleaseDistance` (8m), either enters a vehicle (`Config.drag.releaseInVehicle`), the dragger goes down, or the target recovers (`Config.drag.releaseWhenRecovered`).
```

#### `Police.putInVehicle(officerSrc, targetSrc, netId, seat?) / Police.takeOutVehicle(officerSrc, targetSrc)`

Seats/un-seats a cuffed suspect in a vehicle by network id. `seat` follows the native VehicleSeat enum (-1 driver, 0+ passenger).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `targetSrc` | integer | The suspect/civilian's server id. |
| `netId` | integer |  |
| `seat?` | integer | Default -1 (driver). |

**Returns**

- **ok** — boolean.
- **err** — `not an on-duty officer`, `target is not cuffed`, `too far away`, `vehicle not found`.

**Example**

```lua
Police.putInVehicle(source, target, netId, -1)
```

**Representative console output**

```text
Automatically clears any active escort/drag on the target first.
```

### Limits and related APIs

No per-officer concurrency cap on cuffing. `Config.cuff.verifyWithServer` governs a client that sees itself cuffed asking the server to confirm (resyncCuff callback) rather than trusting local state alone.

### Related guides

- [Search, seizure & robbery](./search-seizure-robbery.md)
- [Jail, citations, impound & plate flags](./jail-citations-impound.md)

## Client

Replicated-state readers (`Police.isPedCuffed`, `Police.isPedRestrained`), the kora_target "Cuff"/"Escort"/"Drag"/"Release" options, the worn-handcuffs prop drawn from the replicated bag (no networked object — works even under `sv_entityLockdown`), and the `/breakcuffs`, `/escort`, `/releasedrag` commands.

Namespace: `Police.* (server), net events kora_police:server:*` · Source: `client/core.lua, client/cuff.lua, client/cuff_escape.lua, client/cuff_prop.lua, client/escort.lua`

### Functions

Legacy client exports: `isHandcuffed()` / `IsHandcuffed()` (also provided under the `qb-policejob` resource identity via `Kora.compat.provideExport`).

### Limits and related APIs

Attachment (escort/drag) is done by each party's OWN client calling `AttachEntityToEntity` on itself — this resource never attempts to move another player's networked ped remotely.
