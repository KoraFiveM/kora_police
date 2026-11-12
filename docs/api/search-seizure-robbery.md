---
title: "Search, seizure & robbery"
sidebar_position: 3
---


# Search, seizure & robbery

Three distinct mechanisms sharing one kora_inventory seam (`registerInspectionAccess`): officer search (any cuffed target), narrow legacy seizures (cash/license), and a non-officer-eligible robbery of any incapacitated player.

Namespace: `Police.* (server)` · Source: `server/seize.lua, server/rob.lua`

## How it works

Both search and rob grant access to the SAME kora_inventory inspection policy rather than duplicating inventory/storage code; the policy function checks `Police.hasRobAccess` first (so a rob grant works even for a non-officer), then falls back to the `Police.isPolice` + cuffed check search relies on.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Inspection access | kora_inventory's `registerInspectionAccess(fn)` seam: a server policy function consulted before letting one player's client open another's inventory as a secondary session. |
| Rob grant | `Police.robGrants[robberSrc] = { target, expires, opened }` — re-validated on every inventory request and swept every `Config.rob.checkInterval` (1s default). |

## Functions

6 Police.* functions, 5 net events (kora_police:server:search/seizeCash/seizeDriverLicense/rob).

### `Police.search(officerSrc, targetSrc)`

Opens the target's inventory as the officer's own secondary session, via kora_inventory's `registerInspectionAccess` policy (registered once at `CreateThread`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `targetSrc` | integer | The suspect/civilian's server id. |

**Returns**

- **ok** — boolean.
- **err** — `not an on-duty officer`, `target is not restrained`, `too far away`.

**Example**

```lua
Police.search(source, target)
```

**Representative console output**

```text
Fires both `kora_police:client:openSearch` and the legacy `police:client:SearchPlayer` to the officer.
```

### `Police.seizeCash(officerSrc, targetSrc)`

Transfers 100% of the target's cash account to the officer.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `targetSrc` | integer | The suspect/civilian's server id. |

**Returns**

- **ok, err, amount** — amount is the integer seized on success.

**Example**

```lua
local ok, err, amount = Police.seizeCash(source, target)
```

**Representative console output**

```text
No cap beyond the target's actual balance; `target has no cash` if zero.
```

### `Police.seizeDriverLicense(officerSrc, targetSrc)`

Sets the target's `licences.driver` metadata flag to false.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `targetSrc` | integer | The suspect/civilian's server id. |

**Returns**

- **ok, err.**

**Example**

```lua
Police.seizeDriverLicense(source, target)
```

**Representative console output**

```text
Mirrors qb-policejob's `metadata.licences` table shape.
```

### `Police.rob(robberSrc, targetSrc)`

Takes cash and/or opens the inventory of ANY incapacitated player (cuffed or downed) — not restricted to police. Cash is capped at 5x the largest `Config.fine.tiers` value and rate-limited per TARGET by `Config.rob.robCooldownSeconds` (300s default); inventory access alone is never rate-limited.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `robberSrc` | integer |  |
| `targetSrc` | integer | The suspect/civilian's server id. |

**Returns**

- **ok, err, amount, waitSeconds** — amount is 0 when only the inventory was opened (e.g. cash on cooldown); waitSeconds is set when cash specifically was refused by the cooldown.

**Example**

```lua
local ok, err, amount, waitSeconds = Police.rob(source, target)
```

**Representative console output**

```text
Grants a time-limited (`Config.rob.accessSeconds`, 120s) secondary-inventory session on the same inspection-access seam search uses; the grant is revoked by a sweep thread (`Police.sweepRobGrants`) when the target recovers or the pair separates past `Config.rob.closeDistance` (4m).
```

### `Police.hasRobAccess(robberSrc, targetSrc)`

Whether `robberSrc` currently holds a valid, unexpired, still-in-range rob grant on `targetSrc`. Consulted by the same `registerInspectionAccess` policy `Police.search` uses.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `robberSrc` | integer |  |
| `targetSrc` | integer | The suspect/civilian's server id. |

**Returns**

- **boolean.**

**Example**

```lua
if Police.hasRobAccess(src, target) then return true end
```

**Representative console output**

```text
Checked BEFORE the `Police.isPolice` requirement in the inspection policy, so a non-officer robber's grant is honored.
```

## Limits and related APIs

Seize cash/license and search all require the target cuffed specifically (not merely downed); only rob extends to a downed-but-uncuffed target.

## Related guides

- [Restraint, escort & transport](./restraint-escort-transport.md)
- [Evidence & forensics](./evidence-forensics.md)
