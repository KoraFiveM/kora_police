---
title: "Commands"
sidebar_position: 4
---


# Commands

All client commands are unrestricted at the command layer — every check (on-duty, cuffed, cuffer, grade, distance) runs server-side in the `Police.*` function the command/event calls into, so a renamed or client-modified command gains nothing.

## Built-in commands

### `/backup`

Requests police backup through kora_dispatch (`kora_police:backup` player alert, code 10-78, priority 2).

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | Must be on-duty police (`Police.isOnDuty()` client-side convenience check; `Police.isLeo` is the real server gate). |

**Example**

```text
/backup
```

**Result**

A dispatch call reaches every on-duty unit of the LEO service, throttled by `Config.dispatch.backupCooldown` (15s default).

### `/escort`

Toggle: starts escorting the nearest cuffed player within reach, or stops escorting/dragging if already doing either.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | On-duty police to START an escort (server-checked via `Police.isPolice`); stopping is available to the officer or the escorted/dragged player. |

**Example**

```text
/escort
```

**Result**

The target is attached just behind the officer and walks with them until `/escort` again, an officer uncuff, or the target escapes/recovers.

### `/breakcuffs`

Attempts to escape a SOFT cuff via a server-authorized mash-style minigame. No effect on a hard (officer-applied) cuff.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | Any soft-cuffed player, subject to `Config.cuff.breakCuffsAttempts` (default 3) and `Config.cuff.breakCuffsCooldown` (60s) between failed tries. |

**Example**

```text
/breakcuffs
```

**Result**

A win releases the cuff and notifies "You broke free!"; a loss or cancel consumes an attempt and starts the cooldown.

### `/releasedrag`

Releases the player currently being dragged. Also bound to a rebindable key (`Config.drag.releaseKey`, default E) while a drag is active.

| Field | Details |
| --- | --- |
| Context | In-game · client command (`Config.drag.releaseCommand`; '' disables it) |
| Arguments | No arguments. |
| Access | Only acts while this player is dragging someone; silently does nothing otherwise. |

**Example**

```text
/releasedrag
```

**Result**

The dragged player is detached and both clients clear their drag state.

### `/spikestrip`

Deploys a spike strip ~2m in front of the officer's facing direction.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | On-duty police only (`Police.isPolice`); capped at `Config.spikes.maxDeployed` (6) concurrent strips per officer. |

**Example**

```text
/spikestrip
```

**Result**

A real networked object appears on the road; it deflates tyres within `Config.spikes.deflateDistance` (1.2m) and expires after `Config.spikes.lifetime` (120s).

### `/police-duty`

Toggles on/off duty. Also reachable via the Police Duty kora_target zone at a configured duty point.

| Field | Details |
| --- | --- |
| Context | Server command (`Kora.events`/`Kora.commands.add`, callable from chat) |
| Arguments | No arguments. |
| Access | Must be employed by `Config.police.job` and standing within a configured duty point's radius (+1m). |

**Example**

```text
/police-duty
```

**Result**

"You are now on duty."/"You are now off duty."; refused with "Use a police duty point to change duty status." away from a duty point, rate-limited by `Config.duty.actionCooldown` (1s).

### `/citations`

Lists the caller's own unpaid citations with id, amount and reason.

| Field | Details |
| --- | --- |
| Context | In-game · server command (`Config.Citations.listCommand`) |
| Arguments | No arguments. |
| Access | Any player; only ever shows their own citations. |

**Example**

```text
/citations
```

**Result**

One notification per unpaid citation, then a hint to pay with `/paycitation [number]`. Not registered at all if `Config.Citations.payMethods.command` is false.

### `/paycitation [number]`

Pays one unpaid citation (the oldest when `number` is omitted) from `Config.fine.account`.

| Field | Details |
| --- | --- |
| Context | In-game · server command (`Config.Citations.payCommand`) |
| Arguments | number? — citation id from `/citations`; defaults to the oldest unpaid one. |
| Access | Any player; only ever pays their own citation. |

**Example**

```text
/paycitation 3
```

**Result**

"You paid citation #3 ($250)." or an affordability/invalid-id error.

## Legacy chat commands this resource does NOT register

Stock qb-policejob/qbx_police command names (e.g. `/cuff`) are not re-registered here — cuffing, search, seizure, jail, billing, tracker and plate-flag actions are reached entirely through kora_target options and the legacy net-event names in `server/compat/police.lua`/`compat/stash.lua`, not chat commands.

## Command summary

| Command | Side | Who | What it does |
| --- | --- | --- | --- |
| `/police-duty` | server | Job `Config.police.job`, at a duty point | Toggles duty. Refused away from every `Config.duty.points` entry (radius plus 1 m) |
| `/backup` | client | On-duty player | Asks the server for a backup call (`10-78`) |
| `/uncuff` | client | Anyone (the server decides) | Releases the nearest cuffed player within `Config.cuff.distance`. Name from `Config.cuff.uncuffCommand`; not registered when `''` |
| `/breakcuffs` | client | Soft-cuffed player | Starts an escape attempt |
| `/escort` | client | On-duty player | Escorts the nearest player; if already escorting or dragging, stops it |
| `/releasedrag` | client | Dragger | Releases the dragged player. Name from `Config.drag.releaseCommand`; not registered when `''`. Does nothing while the target eye is active |
| `/spikestrip` | client | On-duty player | Deploys a spike strip about 2 m ahead |
| `/citations` | server | Any player | Lists your unpaid citations (name from `Config.Citations.listCommand`) |
| `/paycitation [number]` | server | Any player | Pays a citation by number, or the oldest. Name from `Config.Citations.payCommand` |

`/citations` and `/paycitation` exist only when `Config.Citations.payMethods.command` is not `false`.

## Keybinds

Both are `kora_lib` keybinds that players can rebind in their key settings.

| Name | Default | Behaviour |
| --- | --- | --- |
| `kora_police_panic` | `Config.dispatch.panicKey` (`F10`) | On-duty officers raise the panic alarm |
| `kora_police_releasedrag` | `Config.drag.releaseKey` (`E`) | Enabled only while dragging; releases the dragged player. Not registered when `''` |
