---
title: "API reference"
sidebar_position: 1
---

# API reference

| Module | Namespace | Realms |
| --- | --- | --- |
| [Restraint, escort & transport](./restraint-escort-transport.md) | `Police.* (server), net events kora_police:server:*` | server, client |
| [Search, seizure & robbery](./search-seizure-robbery.md) | `Police.* (server)` | server |
| [Evidence & forensics](./evidence-forensics.md) | `Police.* (server)` | server, client |
| [Dispatch & crime detection](./dispatch-crime-detection.md) | `Police.* (server), kora_police:server:* events` | server, client |
| [Duty, fleet, armory & armour](./duty-fleet-armory.md) | `Police.* (server)` | server |
| [Jail, citations, impound & plate flags](./jail-citations-impound.md) | `Police.* (server)` | server |
| [Field tools](./field-tools.md) | `Police.* (server)` | server, client |
| [MDT readiness & legacy compatibility](./legacy-mdt.md) | `Kora.callback / RegisterNetEvent (server)` | server |

## Resource exports

### Server

| Export | Available when | Description |
| --- | --- | --- |
| `getCitations(src)` | `Config.Citations.payMethods.exports` is not `false` | Returns the player's unpaid citations: list of `id`, `amount`, `reason`, `officer`, `issuedAt` |
| `payCitation(src, id)` | same | Pays citation `id` (oldest when `nil`) from `Config.fine.account`; returns `true`, or `false` and a message |
| `CreateBallisticCasing(src, round)` | always | Creates a casing marker and database row for `round` (`id`, `weaponSerial`, `weapon`, `ammoType`, `lot`); returns the case id or `nil`. Needs `Config.evidence.ballistic.enabled` |
| `GetBallisticCasing(caseId)` | always | Returns the `kora_police_ballistic_casings` row for a case id, or `nil` and an error |

`CreateBallisticCasing` is called by this resource's own listener for `kora_inventory:server:weaponRoundFired`; call it yourself only if you need casings from another source.

### Client

| Export | Description |
| --- | --- |
| `isHandcuffed()` and `IsHandcuffed()` | `true` when the local player is cuffed. The capitalised form is also provided as `exports['qb-policejob']:IsHandcuffed` |

### Server Lua helpers (not exports)

The `Police` table is global inside this resource only. Notable functions, all returning `ok, err` unless noted: `Police.cuff`, `Police.uncuff`, `Police.softCuffNearby`, `Police.escort`, `Police.deEscort`, `Police.startDrag`, `Police.stopDrag`, `Police.putInVehicle`, `Police.takeOutVehicle`, `Police.search`, `Police.seizeCash`, `Police.seizeDriverLicense`, `Police.rob`, `Police.bill`, `Police.jailPlayer`, `Police.canAccessArmory`, `Police.impound`, `Police.retrieveImpound`, `Police.flagPlate`, `Police.unflagPlate`, `Police.isPlateFlagged`, `Police.deploySpike`, `Police.spawnObject`, `Police.dispatch(payload)`, plus `Police.isPolice(src, onDutyOnly)`, `Police.isLeo(src)`, `Police.isCuffed(src)`, `Police.isDowned(src)`, `Police.gradeLevel(src)` and `Police.distanceBetween(a, b)`.

### Used from other resources

The resource calls `kora_core` (player data, metadata, money, items, jail, garage), `kora_inventory` (`RegisterShop`, `RegisterStash`, `OpenInventory`, `registerInspectionAccess`, `AddItem`, `RemoveItem`, `GetEquippedWeapon`, and related), `kora_dispatch` (`createCall`, `createPlayerCall`, `registerPlayerAlert`, `setTheme`) and `kora_target` (zones, global options, `setEnabled`, `getState`). Their exact signatures are documented by those resources.
