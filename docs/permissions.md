---
title: Permissions
sidebar_position: 12
---

# Permissions

The resource uses `kora_core` jobs and duty, not ACE permissions, and registers no ACE entries. Chat commands are registered with `Kora.commands.add`; the job and duty checks are done by the server code behind each one.

## Definitions

- **Police**: `Police.isPolice` - job name equals `Config.police.job` and on duty.
- **LEO**: `Police.isLeo` - job type equals `Config.police.jobType` and on duty.
- **Grade**: `job.grade.level` (1 = Cadet, 2 = Officer, 3 = Sergeant, 4 = Lieutenant, 5 = Chief, as in the default config comments).

## Rules

| Action | Requirement |
| --- | --- |
| Cuff, search, seize, escort, put in or take out of vehicle, fingerprint | Police; target cuffed (cuff itself needs an unrestrained officer); within `Config.cuff.distance` |
| Soft cuff (`handcuffs` item) | Any player holding the item |
| Uncuff | Police, the soft-cuffer (if enabled), or the cuffed player after an escape |
| Drag | Any unrestrained player; target cuffed or downed |
| Rob | Any unrestrained player; target cuffed or downed; the target option hides for on-duty officers |
| Citation, jail | Police. Citation also needs the target in range |
| Armory | Police, grade at least the shop `minGrade`, in range |
| Evidence locker, stock stashes | Police, grade at least `Config.evidence.minGradeToAccess` for the locker and drawers |
| Collect evidence | Police, near the marker, with a bag |
| Duty toggle | Job `Config.police.job`, near a duty point |
| Fleet vehicles, plate flags, spikes, props, impound, tracker | Police |
| Backup, panic, helicopter spotlight | LEO |
| Retrieve impound | Any player who owns the vehicle (enforced by `kora_core`) |
| Pay citations | Any player |

Grade checks use the job named in `Config.police.job` only; other LEO jobs get calls but no department access.
