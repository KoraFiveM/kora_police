---
title: kora_police
sidebar_position: 1
---

# kora_police

`kora_police` is the police / law-enforcement job for Kora servers. It covers cuffing (hard and soft), escort and drag, vehicle loading, searching and seizing from restrained players, citations, jail booking, an evidence system with ballistic casings, a grade-gated armory, dispatch calls and a panic button, duty toggling with a patrol fleet, spike strips, road props, plate flags, fingerprints, ankle trackers, vehicle impound and security cameras. Every check that matters (duty, grade, distance, restraint) runs on the server; clients only ask. It also ships a large `qb-policejob` compatibility layer (`provide 'qb-policejob'`) next to its own `kora_police:*` events.

Current version: see `version` in `fxmanifest.lua`.

## Documentation map

- [Installation](./installation.md) - requirements, start order, manifest load order, schema and items summary, first-run setup
- [How to use](./how-to-use.md) - permission model, grade ladder, fingerprints, evidence, dispatch, armory, cuffing, escort, search and seizure
- [Commands and keybinds](./commands.md) - every chat command with arguments, access and results, plus keybinds
- [API reference](./api/index.md) - module overview and the resource exports
  - [Restraint, escort & transport](./api/restraint-escort-transport.md) - cuff, escort, drag and vehicle functions
  - [Search, seizure & robbery](./api/search-seizure-robbery.md) - search, seize and rob functions
  - [Evidence & forensics](./api/evidence-forensics.md) - evidence, ballistic casings and fingerprints
  - [Dispatch & crime detection](./api/dispatch-crime-detection.md) - dispatch calls, panic and detectors
  - [Duty, fleet, armory & armour](./api/duty-fleet-armory.md) - duty toggle, patrol fleet, armory and armour
  - [Jail, citations, impound & plate flags](./api/jail-citations-impound.md) - jail booking, citations, impound and plate flags
  - [Field tools](./api/field-tools.md) - spike strips, road props, trackers and cameras
  - [MDT readiness & legacy compatibility](./api/legacy-mdt.md) - MDT callbacks and the legacy event surface
- [Features](./features.md) - what each feature does and how it behaves
- [Configuration](./configuration.md) - every `Config` table in `config.lua`
- [Player interactions](./ui.md) - `kora_target` options and dialogs
- [Events](./events.md) - `kora_police:*` net events, local events, callbacks
- [Legacy compatibility](./compatibility.md) - `qb-policejob` and `police:*` events and callbacks
- [Items](./items.md) - items registered and items used
- [Permissions](./permissions.md) - job, grade and duty rules per action
- [Database](./database.md) - tables and metadata used
- [Troubleshooting](./troubleshooting.md) - common problems and known caveats

## Testing

- `test/run.sh` runs the offline Lua smoke tests in `test/smoke/` against mocks (`test/mocks.lua`, `test/harness.lua`). They do not start FiveM.
- `tests/checklist-police-and-ems.feature` holds manual QA scenarios for `kora_qa` (registered with `qa_feature` in `fxmanifest.lua`).
