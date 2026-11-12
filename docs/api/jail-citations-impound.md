---
title: "Jail, citations, impound & plate flags"
sidebar_position: 7
---


# Jail, citations, impound & plate flags

Booking a suspect, fining/citing them, impounding and releasing civilian vehicles, and flagging plates for every officer's awareness (with optional kora_mdt BOLO mirroring).

Namespace: `Police.* (server)` · Source: `server/jail.lua, server/bill.lua, server/impound.lua, server/plate_flag.lua`

## How it works

None of these four add new persistence beyond what they wrap: jail and impound lean entirely on `kora_core`'s own jail/garage systems; citations are stored as `citations` metadata (survives relogs/restarts); plate flags are the one purely in-memory registry, with the MDT mirror as the only durable copy when enabled.

## Config.jail / Config.Citations / Config.fine / Config.impound / Config.plateFlags

Pass an options table as the final argument to a play function. Omit the table or any field to use its default.

| Option | Type | Description |
| --- | --- | --- |
| `jail.defaultMinutes` | integer | Fallback sentence length (10) when a booking flow specifies none. |
| `Citations.autoDeduct / maxUnpaid / payMethods / listCommand / payCommand` | boolean / integer / table / string | Whether a fine is charged immediately (nothing stored) or stored for the recipient to pay; the unpaid cap (25); which of command/export access is enabled. |
| `fine.tiers / fine.account` | table / string | Weighted `{amount, weight}` tiers a job script can roll a default fine from; the account (bank) fines/citations deduct from. |
| `impound.fee / maxFee / lots / takeOutDistance` | number / table | Default fee (500), legacy-path cap (10,000), configured lots, and the distance a legacy take-out must be requested from. |
| `plateFlags.mirrorToMdt / days` | boolean / integer | Whether flagging also writes/resolves an active `kora_mdt_bolos` row, and how many days it stays active (7). |

## Functions

9 Police.* functions of note.

### `Police.jailPlayer(officerSrc, targetSrc, minutes?, reason?)`

Thin wrapper over `exports.kora_core:jailPlayer` — adds officer authority, a configured default sentence, and clears escort/drag/cuff (silently) on booking.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `targetSrc` | integer | The suspect/civilian's server id. |
| `minutes?` | number | Default `Config.jail.defaultMinutes` (10). |
| `reason?` | string |  |

**Returns**

- **ok, err.**

**Example**

```lua
Police.jailPlayer(source, target, 15, 'Grand theft auto')
```

**Representative console output**

```text
Teleport/timer/persistence all live in kora_core; this file adds nothing to the jail mechanism itself.
```

### `Police.bill(officerSrc, targetSrc, amount, reason?)`

Issues a citation (stored on the recipient until paid) or, with `Config.Citations.autoDeduct`, charges the fine immediately. Amount is capped at a hardcoded 100,000 and must be a positive integer.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `targetSrc` | integer | The suspect/civilian's server id. |
| `amount` | number |  |
| `reason?` | string | Truncated to 120 characters. |

**Returns**

- **ok, err.**

**Example**

```lua
Police.bill(source, target, 250, 'Reckless driving')
```

**Representative console output**

```text
Unpaid citations are capped at `Config.Citations.maxUnpaid` (25) per player, oldest dropped beyond that.
```

### `Police.payCitation(src, id?)`

Pays one unpaid citation (oldest when `id` is omitted) from `Config.fine.account`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer |  |
| `id?` | integer |  |

**Returns**

- **ok, err.**

**Example**

```lua
Police.payCitation(source)
```

**Representative console output**

```text
Backs `/paycitation` and the `payCitation` export.
```

### `Police.getCitations(src)`

Lists a player's unpaid citations, oldest first.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer |  |

**Returns**

- **`table[]`** — a copy of the stored citation records; empty when the player has none.

**Example**

```lua
local citations = Police.getCitations(source)
```

**Representative console output**

```text
Also available to other resources as `exports.kora_police:getCitations(src)` (for a phone or bank UI), unless `Config.Citations.payMethods.exports` is `false`.
```

### `Police.impound(officerSrc, plate, lotId?, opts?) / Police.retrieveImpound(src, plate)`

Entirely on `Core.garage` — no new persistence. `Police.impoundedPlates` is only a local index (for the MDT-readiness `GetImpoundedVehicles` callback), not the source of truth.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `plate` | string |  |
| `lotId?` | string |  |
| `opts?` | &#123; fee?: number, full?: boolean &#125; |  |

**Returns**

- **ok, err.**

**Example**

```lua
Police.impound(source, 'ABC123')
```

**Representative console output**

```text
Fee defaults to `Config.impound.fee` (500), capped by `Config.impound.maxFee` (10,000) via the legacy path.
```

### `Police.flagPlate(officerSrc, plate, reason?) / Police.unflagPlate(officerSrc, plate) / Police.isPlateFlagged(plate)`

An in-memory BOLO registry, optionally mirrored into `kora_mdt_bolos` as an active vehicle BOLO when `Config.plateFlags.mirrorToMdt` is on and kora_mdt is running.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `plate` | string |  |
| `reason?` | string | Defaults to `BOLO`. |

**Returns**

- **ok, err (flag/unflag); flagged, entry (isPlateFlagged).**

**Example**

```lua
Police.flagPlate(source, 'ABC123', 'Suspect vehicle')
```

**Representative console output**

```text
Unflagging also resolves any mirrored active MDT BOLO even if nothing remains in local memory (covers a flag set before a restart or raised directly in the MDT).
```

## Limits and related APIs

Plate flags do not survive a restart unless mirrored to kora_mdt; `Police.impoundedPlates` is a read index only, never consulted for authorization.

## Related guides

- [Duty, fleet, armory & armour](./duty-fleet-armory.md)
- [MDT readiness & legacy compatibility](./legacy-mdt.md)
