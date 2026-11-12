---
title: "Dispatch & crime detection"
sidebar_position: 5
---


# Dispatch & crime detection

## Server

The police-specific layer on top of kora_dispatch: fixed alert wording/priority for backup, gunfire (plain and suppressed), vehicle theft and melee; the officer-down panic button (two separate calls, LEO + EMS); and the cop-count broadcast kept for legacy heist/robbery scripts.

Namespace: `Police.* (server), kora_police:server:* events` · Source: `server/dispatch.lua`

### How it works

Police does not implement call presentation, map rendering or the response state machine itself — that is entirely `kora_dispatch`'s job (see the Kora Dispatch page). What lives here is the police-specific wording and the decision that an incident IS a police matter: five fixed alert definitions are registered once at boot with `exports.kora_dispatch:registerPlayerAlert` — `kora_police:backup`, `kora_police:gunfire`, `kora_police:gunfire:suppressed`, `kora_police:vehicle-theft`, `kora_police:melee` — each with its own code, title, message, priority, icon and per-type cooldown pulled from `Config.dispatch`. **Automatic detection** (`client/detectors.lua`) polls every 500ms for shooting (`IsPedShooting`), vehicle theft/jacking attempts and melee combat, and reports the incident key to `kora_police:server:crimeDetected` — never a priority, service or coordinate, which the server-side registration alone supplies. On-duty officers are excluded from every detector (so a firearms unit returning fire never calls itself in). Detectors are throttled, not debounced, so an ongoing incident reports immediately rather than waiting for it to stop. **`/backup`** (client command) calls `kora_police:server:requestBackup`, which requires `Police.isLeo` and raises `kora_police:backup` through `exports.kora_dispatch:createPlayerCall`. **The panic button** (`F10` by default, `Config.dispatch.panicKey`) raises TWO separate calls — one to the LEO service (`10-99 Officer Down`, priority 1) and a second, independent one to `Config.police.emsJobType` (default `ems`, `10-52`, priority 1) — because police and EMS keep separate feeds and histories; bundling them would force one shared feed neither service could clear independently. Both calls read the officer's position server-side from their own ped. A 60-second-default cooldown (`Config.dispatch.panicCooldown`) stops one mashed key-press from filling both feeds with duplicates of the same incident; going off duty clears the cooldown immediately (a new shift is a new emergency). **Cop-count broadcasting**: `Police.broadcastCopCount()` fires on duty/job changes and pushes the on-duty LEO count (by job TYPE) to `kora_police:client:updateCopCount`, the legacy `police:client:UpdateCurrentCops`/`police:client:SetCopCount` events to on-duty officers, and a bare `police:SetCopCount` broadcast to literally everyone (heist/robbery scripts read this; the count itself is not considered secret).

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Service vs. job name | A kora_dispatch call targets a job TYPE (service), not a job name — see Kora Dispatch's own "Services, not jobs" section. `Police.isLeo` is the type-based gate; `Police.isPolice` is the name-based one used everywhere else in this resource. |

### Config.dispatch / Config.police (config.lua)

Pass an options table as the final argument to a play function. Omit the table or any field to use its default.

| Option | Type | Description |
| --- | --- | --- |
| `police.job / police.jobType / police.emsJobType` | string | The job name this resource gates on (`police`), the job TYPE dispatch calls target (`leo`), and the SECOND service a panic alarm also calls (`ems`). |
| `panicKey / panicCooldown / backupCooldown` | string / integer | F10 by default; 60s / 15s cooldowns. |
| `shotsFiredCooldown / vehicleTheftCooldown / meleeCooldown` | integer | Per-detector-type alert cooldowns (20s / 30s / 30s). |
| `legacyAlertCooldown / legacyAlertMaxLength / copCountThrottle` | integer | Throttle and length cap for the legacy `police:server:policeAlert` compat path; broadcast throttle for legacy cop-count requests. |

### Functions

3 Police.* functions of note, plus `kora_police:server:requestBackup`, `kora_police:server:panic` and `kora_police:server:crimeDetected` (Kora.events, rate-limited).

#### `Police.dispatch(payload)`

Raises a law-enforcement call. Defaults `jobTypes` to `{ Config.police.jobType }` (the whole LEO service, not just this job name) when the caller supplies neither `jobs` nor `jobTypes`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | table | Same shape as `exports.kora_dispatch:createCall`'s payload. |

**Returns**

- **callId, recipientCountOrError** — passthrough of `exports.kora_dispatch:createCall`.

**Example**

```lua
Police.dispatch({ code = '10-60', title = 'Police Alert', message = text, priority = 2, coords = coords })
```

**Representative console output**

```text
Also fills `payload.radius` from `Config.dispatch.robberyRadius` if unset.
```

#### `Police.isLeo(src)`

Whether `src` is on-duty in ANY job whose kora_core job TYPE equals `Config.police.jobType` (default leo) — not just the `police` job name. Used for every dispatch-facing gate (panic, backup, crime detection).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer |  |

**Returns**

- **boolean.**

**Example**

```lua
if Police.isLeo(src) then ... end
```

**Representative console output**

```text
A sheriff or state-trooper job sharing the `leo` type passes this just as the police job does.
```

#### `Police.panicCooldownElapsed(src)`

Whether `src` may raise another panic alarm right now.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer |  |

**Returns**

- **elapsed** — boolean.
- **remainingMs** — integer, 0 when elapsed.

**Example**

```lua
local ok, remaining = Police.panicCooldownElapsed(src)
```

**Representative console output**

```text
Cooldown is `Config.dispatch.panicCooldown` (60s default); cleared immediately on going off duty.
```

### Limits and related APIs

Dispatch presentation (the feed, map, response state machine) is entirely kora_dispatch's responsibility — nothing here renders a call.

### Related guides

- [Duty, fleet, armory & armour](./duty-fleet-armory.md)
- [MDT readiness & legacy compatibility](./legacy-mdt.md)

## Client

The `/backup` command, the panic keybind (`Config.dispatch.panicKey`), cop-count listeners for other UI, and the five-incident automatic crime detector loop (500ms poll, throttled not debounced, off-duty officers only).

Namespace: `Police.* (server), kora_police:server:* events` · Source: `client/dispatch.lua, client/detectors.lua`

### Functions

No client exports.
