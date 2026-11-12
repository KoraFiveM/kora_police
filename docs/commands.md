---
title: Commands and keybinds
sidebar_position: 5
---

# Commands and keybinds

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
