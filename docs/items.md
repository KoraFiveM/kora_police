---
title: Items
sidebar_position: 11
---

# Items

## Registered by this resource

`server/items.lua` registers these in the `kora_core` shared items at start:

| Item | Label | Useable | Behaviour |
| --- | --- | --- | --- |
| `handcuffs` | Handcuffs | yes | Soft-cuffs the single nearest player (the item is not consumed) |
| `moneybag` | Money Bag | yes | Pays out `info.amount` as cash and removes the bag; rolls back if payment fails |
| `armor` | Bulletproof Vest | yes | Body armour (see below) |

## Armour items

`Config.armour.items` registers usable handlers for `armor`, `armour` and `heavyarmor`. `armour` and `heavyarmor` are not registered by this resource, so they must exist in the shared items for players to hold them.

## Evidence items

- `empty_evidence_bag` is consumed to collect a casing, blood drop or fingerprint (`Config.evidence.bagItem`). It is issued free by the Patrol Armory.
- `filled_evidence_bag` is given with `info.label`, `info.type` (`ballistic_casing`, `blood`, `fingerprint` or `casing`), and `caseId`, `dnalabel` or `fingerprint` depending on type.

Both exist in the `kora_core` shared items catalog; they are not registered here.

## Armory stock

Defaults: Patrol (`weapon_stungun`, `weapon_nightstick`, `handcuffs`, `pistol_ammo`, `armor`, `empty_evidence_bag`, all free), Sergeant (`weapon_combatpistol`, `weapon_pumpshotgun`, `shotgun_ammo`, `rifle_ammo`) and SWAT (`weapon_carbinerifle`, `rifle_ammo`). Every name must exist in the shared items or weapons.
