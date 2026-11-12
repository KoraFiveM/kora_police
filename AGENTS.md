# kora_police agent guide

`kora_police` is the Kora police / law-enforcement job resource: cuffing, escort and drag, search and seizure, citations, jail booking, evidence and ballistic casings, a grade-gated armory, dispatch calls, duty and patrol fleet, spike strips, plate flags, trackers and impound, plus a `qb-policejob` compatibility layer. Layout: `fxmanifest.lua` (explicit script load order), `config.lua` (single `Config` table), `server/` (shared `Police` table in `core.lua`, one file per feature, `compat/` for legacy events), `client/` (target options, animations, detectors), `test/smoke/` (offline Lua regression tests) and `tests/` (kora_qa feature files).

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first for an overview of features, configuration, commands, exports, events and database usage. Layout: `docs/index.md` (hub and documentation map), `installation.md` (requirements, manifest, first run), `how-to-use.md` (behaviour guide), `commands.md` (chat commands and keybinds), `api/` (`index.md` plus one page per `Police.*` module; resource exports live in `api/index.md`), and topic pages (`features`, `configuration`, `ui`, `events`, `compatibility`, `items`, `permissions`, `database`, `troubleshooting`).

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Feature and behaviour changes must update the matching docs in the same change.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
