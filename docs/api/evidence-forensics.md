---
title: "Evidence & forensics"
sidebar_position: 4
---


# Evidence & forensics

## Server

Two independent evidence mechanisms (the kora_inventory evidence-locker stash, and a thin legacy world-evidence marker registry) plus the one durable, server-owned forensic record type this resource has: ballistic casings. Fingerprints are a deterministic per-citizen id surfaced only to an officer searching a cuffed suspect.

Namespace: `Police.* (server)` · Source: `server/evidence.lua, server/fingerprint.lua, server/schema.lua, server/migrate.lua`

### How it works

Two independent mechanisms share the name "evidence", and they do not talk to each other: 1. **The evidence locker** — a single kora_inventory STASH (`RegisterStash`, `Config.evidence.lockerStashId`, default `police-evidence`) registered at `CreateThread` and again on every `kora_inventory` `onResourceStart` (a kora_inventory restart wipes its own stash table independent of start order). Gated by `{ [Config.police.job] = Config.evidence.minGradeToAccess }` — grade 1 by default, i.e. every officer. This is where seized items/packaged samples actually get stored; it uses zero new inventory code. 2. **Legacy "world evidence" markers** (blood drops, casings, fingerprints) — a deliberately thin in-memory registry (`Police.worldEvidence`, id → `{ type, coords, ownerId, bucket, createdAt, expiresAt }`), kept only so the stock `evidence:server:Create*`/`evidence:server:Add*ToInventory`/`evidence:server:Clear*` event names still behave sanely for a third-party script. It is not a CSI minigame: creating a marker is rate-limited per player (`Config.evidence.createCooldown`, 250ms) and capped globally (`Config.evidence.maxWorldMarkers`, 500 — oldest evicted first); collecting one requires `Police.isPolice`, the same routing bucket, `Config.evidence.collectDistance` (2.5m), and consumes one `Config.evidence.bagItem` (`empty_evidence_bag`) to produce a `filled_evidence_bag` with type-specific metadata (a DNA-style hex label for blood, the deterministic fingerprint id for prints, the case id for ballistic casings). **Ballistic casings are the one durable, server-authoritative evidence type.** `Police.createBallisticCasing(src, round)` only runs from the `kora_inventory:server:weaponRoundFired` event — kora_inventory has already server-validated the weapon and consumed the round before this fires, so the client supplies nothing trustworthy. A case id (`CS-<unixtime>-<rand6>-<rand6>`) is minted, a world-evidence marker is created with `ballistic = { caseId, roundId, weaponSerial, weapon, ammoType, lot }`, and a row is inserted into `kora_police_ballistic_casings` — the serial, round id and lot stay server-only; only the collected `filled_evidence_bag` gets a label and case id. `Police.getBallisticCasing(caseId)` (exported as `GetBallisticCasing`) is the one read path for an MDT investigation feature to look up a casing by id; there is no client event that exposes the row.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| World evidence marker | `Police.worldEvidence[id] = { type, coords, ownerId, bucket, createdAt, expiresAt, ballistic? }` — in-memory only, capped at `Config.evidence.maxWorldMarkers` (500), expires after `Config.evidence.worldMarkerTtl` (30 min). |
| Evidence locker | A kora_inventory STASH (`Config.evidence.lockerStashId`), not a bespoke container — reuses all of kora_inventory's existing slot/weight/access/persistence machinery. |

### Config.evidence (config.lua)

Pass an options table as the final argument to a play function. Omit the table or any field to use its default.

| Option | Type | Description |
| --- | --- | --- |
| `lockerStashId / lockerLabel / lockerSlots / lockerMaxWeight / lockerCoords / lockerDistance` | string / integer / vector4 / number | The evidence-locker stash's identity, capacity and world placement. |
| `minGradeToAccess` | integer | job.grade.level required to open the locker and evidence drawers (default 1 — every officer). |
| `bagItem / bagLabel / missingBagMessage` | string | Item consumed to collect a world-evidence sample; shown in the "you need an X" message when missing. |
| `createCooldown / worldMarkerTtl / maxWorldMarkers / collectDistance` | integer / number | Per-player marker-creation throttle (250ms), marker lifetime (30 min), global cap (500, oldest evicted), and collection distance (2.5m). |
| `ballistic.enabled / casingOffset / databaseRetentionDays / analysis` | boolean / number / table | Whether fired rounds leave casings, the randomised landing offset (0.75m), a retention hint (90 days, cleanup not scheduled here), and the configured multi-stage analysis minigames (`skillbar`, `circuit`, `pinpad`) for an investigation feature. |

### Functions

4 Police.* functions of note (ballistic create/read, fingerprint get/reveal) plus the world-evidence marker lifecycle (create/collect/expire) reachable only through legacy `evidence:server:*` events, not direct exports.

#### `Police.createBallisticCasing(src, round)`

Creates a durable, server-authoritative casing record from a kora_inventory-validated fired round. Only ever called from the `kora_inventory:server:weaponRoundFired` event — never reachable with client-supplied round data.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer |  |
| `round` | table | `{ id, weaponSerial, weapon, ammoType?, lot? }` — all already validated by kora_inventory. |

**Returns**

- **caseId** — string (`CS-<unixtime>-<rand6>-<rand6>`), or nil if `Config.evidence.ballistic.enabled` is false or the round is malformed.

**Example**

```lua
AddEventHandler('kora_inventory:server:weaponRoundFired', function(src, round)
    Police.createBallisticCasing(tonumber(src), round)
end)
```

**Representative console output**

```text
Inserts into `kora_police_ballistic_casings` asynchronously; also drops a collectible world-evidence marker at a randomised offset from the shooter.
```

#### `Police.getBallisticCasing(caseId)`

Server-only lookup of a full casing row (including `weapon_serial`) for an authorised MDT investigation feature. No client event exposes this.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `caseId` | string |  |

**Returns**

- **row** — table, or nil + `invalid case id`.

**Example**

```lua
local row = exports.kora_police:GetBallisticCasing(caseId)
```

**Representative console output**

```text
Exported as `GetBallisticCasing`.
```

#### `Police.getFingerprint(citizenId)`

Deterministic per-citizen fingerprint id — see "Fingerprints: current, verified behavior" in How to use for the exact generation logic.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenId` | string |  |

**Returns**

- **fingerprint** — 10-character numeric string.

**Example**

```lua
local id = Police.getFingerprint(citizenid)
```

**Representative console output**

```text
Cached for the life of the server process; not persisted.
```

#### `Police.getFingerprintForOfficer(officerSrc, targetSrc)`

The only path that reveals a fingerprint: requires `Police.isPolice`, the target cuffed, and both within `Config.cuff.distance`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `officerSrc` | integer | The acting officer's server id. In a net-event handler this is always `source`, never a client-supplied argument. |
| `targetSrc` | integer | The suspect/civilian's server id. |

**Returns**

- **fingerprint** — string, or nil on any failed check.

**Example**

```lua
Kora.callback.register('kora_police:server:getFingerprint', function(src, target)
    return Police.getFingerprintForOfficer(src, target)
end)
```

**Representative console output**

```text
Backs the "Check Fingerprint" kora_target option on a cuffed player.
```

### Limits and related APIs

World evidence is NOT a durable record — only ballistic casings are. A resource restart clears every unconverted world-evidence marker and the fingerprint cache.

### Related guides

- [Search, seizure & robbery](./search-seizure-robbery.md)
- [MDT readiness & legacy compatibility](./legacy-mdt.md)

## Client

Opens the evidence locker stash via a kora_target option; renders world-evidence markers as blips with a collect option for on-duty officers; shows a fingerprint result via a local notification.

Namespace: `Police.* (server)` · Source: `client/evidence.lua, client/fingerprint.lua`

### Functions

No client exports; purely event-driven presentation.
