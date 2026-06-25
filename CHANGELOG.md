# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- `AgentMonitorCore` library (models, JSONL parser, status grouping, formatting) with unit tests.
- `scripts/make-app.sh` to package a double-clickable, menu-bar-only `.app`.

[0.1.0]: https://github.com/wynnwu/agent-monitor/releases/tag/v0.1.0
