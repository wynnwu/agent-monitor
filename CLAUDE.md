# CLAUDE.md — Agent Monitor

Context for Claude Code working in this repo. Read `docs/DISCOVERY.md` first — it is the data foundation everything here depends on.

## What we're building

A small **native macOS menu-bar app** that shows which Claude Code sessions are running on this Mac, their live idle/busy status, and lets you open any session's conversation in a detail window. A local, personal observability tool — no network, no telemetry.

Form factor: **menu-bar + detail window**.
- **Menu-bar (`MenuBarExtra`)**: status-bar icon with a badge (count of busy/working agents). Click → popover with a glanceable list of sessions (status dot, name, cwd, kind). Each row has "Open".
- **Detail window**: a transcript viewer for the selected session — renders the user/assistant turns and follows new ones live.

## Tech stack & key decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Language / UI | **Swift 5.9+, SwiftUI** | Lightest native path; `MenuBarExtra` + `WindowGroup` cover both surfaces with no deps. |
| Min target | **macOS 14.0 (Sonoma)** | Lets us use `@Observable`, modern `MenuBarExtra`, `.windowResizability`. |
| State | `@Observable` model objects (Observation framework) | Simpler than `ObservableObject`/`@Published` for this size. |
| Dependencies | **none** (Apple frameworks only) | It's a small tool; keep it dependency-free. |
| Data: status | spawn `claude agents --json --all` on a `Timer` (~2s) | Supported, TTY-free scripting surface. |
| Data: content | glob `~/.claude/projects/*/<sessionId>.jsonl`, then watch with `DispatchSource` | Robust path resolution; append-only incremental reads. |

Do **not** add networking, analytics, or third-party packages without being asked. Do **not** reconstruct the project-dir slug — always glob by `sessionId` (see DISCOVERY §2).

## Architecture

```
AgentMonitorApp (@main, Settings-only scene)
└── AppDelegate (@NSApplicationDelegateAdaptor)            ← owns the menu-bar surface
    ├── NSStatusItem + DropdownPanel → PopoverRootView → SessionListView (3 columns)
    │     (borderless NSPanel centered at top of screen, flush under the menu bar)
    ├── GlobalHotKey (optional, opt-in via Settings) toggles the panel; Esc closes it
    └── NSWindow per session         → TranscriptView (detail window)

(MenuBarExtra was the original plan, but it offers no API to open the popover
programmatically — needed for the global hotkey — nor to position/center it. So the
menu-bar surface is a hand-rolled NSStatusItem + custom NSPanel dropdown, dismissed
via click-outside / Esc / icon toggle. SwiftUI still renders all the content.)

Model layer (@Observable, no UI):
├── AgentService      polls `claude agents --json --all`, publishes grouped [AgentSession]
├── ClaudeCLI         locates the binary, runs it, decodes JSON (Codable)
├── TranscriptStore   resolves + reads (last ~12 turns) + watches one session's .jsonl
├── TranscriptParser  JSONL line → TranscriptRecord (defensive, tolerant of unknown types)
└── GlobalHotKey      Carbon RegisterEventHotKey wrapper (dependency-free)
```

Data flow: `AgentService` is the single source of truth for the session list; `TranscriptStore` is created on demand when a detail window opens for a `sessionId`.

### Core types (sketch — adjust as you build)

```swift
struct AgentSession: Identifiable, Codable, Hashable {
    var id: String { sessionId }
    let sessionId: String
    let cwd: String
    let kind: Kind            // .interactive | .background
    let status: Status?       // .idle | .busy   (per-turn activity)
    let state: State?         // .working | .done (background lifecycle; nil for interactive)
    let name: String?         // AI-generated slug; may be nil
    let pid: Int?
    let startedAt: Double?    // epoch MILLISECONDS
    enum Kind: String, Codable { case interactive, background }
    enum Status: String, Codable { case idle, busy }
    enum State: String, Codable { case working, done }
}
```
Use `decodeIfPresent` for everything except `sessionId`/`cwd`/`kind`; the schema differs by `kind` and drifts across CLI versions.

## Critical implementation gotchas (from DISCOVERY §5)

1. **GUI apps don't inherit your shell `PATH`.** `ClaudeCLI` must resolve the binary explicitly — check `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, `$HOME/.claude/local/claude` (this machine: `~/.local/bin/claude`). Surface a clear error if not found.
2. **The transcript format is internal & version-dependent.** Defensive-parse: tolerate unknown `type` values, missing fields, schema drift. Never crash on an unexpected record.
3. **Buffer the trailing partial line** when reading a file mid-write — only parse up to the last `\n`; keep the remainder for the next read.
4. **No push API** — poll status **adaptively** (10s while any agent is working / the popover is open / state just changed; back off ×2 up to 30s when idle) and watch transcript files with `DispatchSource.makeFileSystemObjectSource`. Don't busy-loop. Transcript content is cached per `(sessionId, fileSize)`, so unchanged files aren't re-read.
5. **Privacy** — transcripts contain full conversation content. Read only; never transmit. No logging of transcript bodies.

## Sandboxing & distribution

Reading `~/.claude/` (outside an App Sandbox container) and spawning `claude` make the **App Sandbox impractical**. Ship **un-sandboxed, Developer ID–signed** for personal use. Make it a status-bar-only app: set `LSUIElement` / `NSApp.setActivationPolicy(.accessory)` so there's no Dock icon (the detail window still opens on demand).

## Project layout (target)

```
agent-monitor/
├── CLAUDE.md                 ← this file
├── README.md
├── docs/DISCOVERY.md         ← data-source reference (read first)
├── scripts/agent-snapshot.sh ← shell reference impl of the core data access
└── AgentMonitor/             ← Swift app (created in M0)
    ├── AgentMonitorApp.swift
    ├── Models/   (AgentSession, TranscriptRecord)
    ├── Services/ (ClaudeCLI, AgentService, TranscriptStore, TranscriptParser)
    └── Views/    (SessionListView, SessionRowView, TranscriptView)
```

## Build & run

The Swift app does not exist yet — M0 creates it. Two viable setups:

- **Xcode project (recommended for a GUI app):** create a macOS App (SwiftUI) target named `AgentMonitor`. Headless builds for verification:
  ```bash
  xcodebuild -scheme AgentMonitor -destination 'platform=macOS' build
  ```
- **SwiftPM executable (agent-friendly, no .xcodeproj):** `swift build` / `swift run`; set `.accessory` activation policy in code instead of an Info.plist. Good if you want everything buildable from the CLI.

**Decision (M0): SwiftPM executable** (no `.xcodeproj`). Build `swift build`; run `swift run AgentMonitor`; test `swift test`. `.accessory` activation policy is set in code (`AgentMonitorApp`). Layout: pure, fully-tested logic in the `AgentMonitorCore` library target; IO + SwiftUI in the `AgentMonitor` executable; unit tests in `AgentMonitorCoreTests`. Chosen UI = **"Triage"** (see `docs/superpowers/specs/2026-06-25-agent-monitor-design.md`; build plan in `docs/superpowers/plans/`).

Validate the data layer directly with:
```bash
./scripts/agent-snapshot.sh            # list sessions (mirrors AgentService)
./scripts/agent-snapshot.sh <name>     # follow a session (mirrors TranscriptStore)
```

## Conventions

- SwiftUI + `@Observable`; keep views thin, logic in services.
- No force-unwraps on decoded data. No third-party deps.
- Follow TDD where it fits: `TranscriptParser` is pure and unit-testable — feed it sample JSONL lines (including a malformed/partial one) and assert the parsed records. Sample fixtures can be lifted from a real `.jsonl` (scrub anything sensitive).
- Keep `docs/DISCOVERY.md` authoritative for data-source facts; if CLI behavior changes, update it there, not inline in code comments.

## Roadmap

- **M0 — Scaffold.** `git init`; create the `AgentMonitor` app target (Xcode or SPM); `MenuBarExtra` shows a static "Hello" popover; record the build choice here.
- **M1 — Live list.** `ClaudeCLI` + `AgentService` poll `claude agents --json --all`; popover renders real sessions with status dots and a busy-count badge.
- **M2 — Transcript viewer.** `TranscriptStore` resolves via glob + reads history; detail window renders user/assistant turns; "Open" from a row works.
- **M3 — Live follow.** Watch the `.jsonl` with `DispatchSource`; append new turns incrementally; auto-scroll.
- **M4 — Polish.** Empty/error states, binary-not-found UX, busy badge, optional sub-agent/workflow drill-in (DISCOVERY §3), launch-at-login.

## Out of scope (for now)

Controlling sessions (sending input, killing), remote/multi-machine monitoring, anything that writes to `~/.claude/`. Read-only observation only.
