# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-06-28

### Fixed
- Sessions sitting at a shell — or blocked on a permission prompt — no longer show as
  **Working**. `claude agents --json` collapses the finer `shell`/`waiting` states into
  `busy`; Agent M now reads the per-PID session registry (`~/.claude/sessions/<pid>.json`)
  and prefers its un-collapsed status (guarded against PID reuse).
- The status poll can no longer hang indefinitely. Spawned `claude` calls now have a
  15-second watchdog that terminates a stuck process instead of wedging the poller.

### Changed
- The full session status vocabulary is recognized and mapped: interactive
  `busy` / `shell` / `idle` / `waiting`, and background
  `working` / `blocked` / `done` / `failed` / `stopped`. A `waiting` interactive session
  (permission prompt / input request) and a `blocked` background job now land in
  **Waiting for you**. See `docs/DISCOVERY.md` for the authoritative mapping.

## [0.1.1] - 2026-06-26

### Added
- An app icon, shown in Finder and on the `.dmg`.
- List rows: the prompt now wraps to two lines, and the git-branch pill is larger.

### Changed
- Renamed the app and bundle to **Agent M** (bundle id `xyz.joystudios.agent-m`).
- Detail window: the git branch moved to a top-right pill (matching the list), and the
  metadata line (model · kind · pid · uptime · id) is larger.
- The default global shortcut is now **⌥M** (still opt-in / disabled by default).

## [0.1.0] - 2026-06-26

First release.

### Added
- Menu-bar status item with a badge of how many agents are active.
- A centered, glass (vibrancy) dropdown that slides down from behind the menu bar, with
  three columns — **Idle**, **Waiting for you**, **Working** — showing up to five rows each
  before fading overlay scrollbars kick in; empty columns stay visible.
- Each row shows the folder, last prompt, directory path, git branch, a status dot, and the
  relative last-active time.
- A live transcript window per session: renders user/assistant turns, follows new turns,
  flags when a session is waiting for your reply, shows a header with model · branch · kind ·
  pid · uptime · session id, and filters to All / Prompts / Responses.
- Adaptive status polling (~10s while active, backing off to 30s when idle) plus live
  `DispatchSource` transcript watching, with reads cached per file size.
- An optional, opt-in global shortcut (Settings → enable and record a combo) to toggle the
  dropdown from anywhere; Esc, click-away, and the icon also dismiss it.
- `AgentMCore` library (models, JSONL parser, status grouping, formatting) with unit tests.
- `scripts/make-app.sh` to package a double-clickable, menu-bar-only `.app`.

[0.1.2]: https://github.com/wynnwu/agent-m/releases/tag/v0.1.2
[0.1.1]: https://github.com/wynnwu/agent-m/releases/tag/v0.1.1
[0.1.0]: https://github.com/wynnwu/agent-m/releases/tag/v0.1.0
