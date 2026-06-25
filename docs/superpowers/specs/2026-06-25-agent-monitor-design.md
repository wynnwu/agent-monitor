# Agent Monitor — Design Spec

**Date:** 2026-06-25 · **Status:** approved (UI direction chosen) · **Supersedes:** the sketch in `CLAUDE.md`

A small, native macOS **menu-bar app** that shows which Claude Code sessions are running on this Mac, their live status, and lets you open any session's conversation. Local, personal, read-only. No network, no telemetry, no dependencies.

Read `docs/DISCOVERY.md` for the data foundation; this spec assumes it.

---

## 1. Goal & the four glance-priorities

For every session, surfaced **at a glance** in the menu-bar popover:

| # | What | Source |
|---|------|--------|
| a | **Directory** it runs in | `cwd` from `claude agents --json` |
| b | **Last prompt** it's working / worked on | last real `user` turn in the transcript JSONL |
| c | **Status** | `status` (idle/busy) + `state` (working/done) from the CLI |
| d | **Waiting on you?** | derived: interactive + idle ⇒ "your turn" (see §4) |

Secondary "geeky" metadata, shown small and never crowding the four: git branch, model (e.g. *Opus 4.8*), conversation length (record count), kind (interactive/background), relative last-active time.

**Principles:** YAGNI ruthlessly; beautiful and minimal; read-only observation only.

---

## 2. Chosen UI — Direction A: "Triage"

A calm, scannable status board that answers one question: *what needs me now?* (Linear/Things aesthetic; mono-accent.) Chosen over "Pulse" (recency-feed) and "Mission Control" (card grid) because it puts **(d) waiting-on-you at the literal top**, is the most minimal/scannable, and is the lowest-effort to build. We graft one idea from Pulse: a subtle live pulse on the "Working now" rows.

### Menu-bar
- `MenuBarExtra` with a small monochrome glyph. **Badge = count of active agents** (interactive `busy` + background `running`). No badge when zero.

### Popover (~380 pt wide, translucent dark material)
Three labeled sections, in order:

1. **Your turn · N** — interactive + idle sessions, **sorted most-recent-first**. The hero band; amber accent (`#F5A623`). This is data point (d).
2. **Working now · N** — interactive `busy` + background `running`; each with a gentle green (`#30D158`) **pulse** dot.
3. **Recently done · N** — background `done` (and, later, stale items); **dimmed**, visually de-emphasized, collapsible.

**Row anatomy** (one glanceable unit):
- left: status dot (amber / pulsing-green / blue `#0A84FF` / gray `#8E8E93`)
- primary: **folder name** (semibold) + dimmed `parent` path
- secondary: **last prompt**, one line, ellipsised
- right: relative time + a small git-branch chip
- on hover: reveal model · message count · kind (so they never crowd the default view)

A row's **Open** action (whole row is clickable) opens the detail window for that `sessionId`.

### Detail window (transcript viewer)
- Renders `user` / `assistant` turns from the resolved `.jsonl`; tool calls shown compactly (`[tool: Bash]`), tool results collapsed.
- Header: folder · branch · model · status. If the session is "your turn," a slim **"Waiting for you"** banner.
- Follows new turns live and auto-scrolls (M3).

Empty / error states (M4): "No sessions running"; "Couldn't find the `claude` binary" with the searched paths.

---

## 3. Architecture

`@Observable` model objects; thin SwiftUI views; logic in services. No third-party packages.

```
AgentMonitorApp (@main, .accessory activation policy — no Dock icon)
├── MenuBarExtra ──→ SessionListView   (popover: TriageSection × 3 of SessionRowView)
└── WindowGroup  ──→ TranscriptView     (detail window, opened per sessionId)

Models (@Observable, no UI):
├── AgentService     polls `claude agents --json --all` on a ~2s Timer → publishes [AgentSession], grouped
├── ClaudeCLI        locates the binary, runs it TTY-free, decodes JSON (Codable)
├── TranscriptStore  resolves (glob by sessionId) + reads history + watches one session's .jsonl
└── TranscriptParser pure: JSONL line → TranscriptRecord; tolerant of unknown types / drift / partial lines
```

**Data flow:** `AgentService` is the single source of truth for the list. `TranscriptStore` is created on demand when a detail window opens. The popover's **last-prompt** line also needs transcript data — see §4 (lightweight, cached).

### Core type
```swift
struct AgentSession: Identifiable, Codable, Hashable {
    var id: String { sessionId }
    let sessionId: String
    let cwd: String
    let kind: Kind                 // .interactive | .background
    let status: Status?            // .idle | .busy
    let state: State?              // .working | .done  (background only)
    let name: String?              // AI slug; usually nil for interactive
    let pid: Int?
    let startedAt: Double?         // epoch MILLISECONDS
    enum Kind: String, Codable { case interactive, background }
    enum Status: String, Codable { case idle, busy }
    enum State: String, Codable { case working, done }
}
```
`decodeIfPresent` for everything except `sessionId`/`cwd`/`kind`. Display helpers (folder = `cwd` lastPathComponent, parent path with `~`, relative time from `startedAt`/last-activity) live in a view-model extension, not the wire type.

---

## 4. Derivation rules (validated against real data, 14 live sessions)

**Status bucket** (the section a session lands in):
- `kind == .interactive && status == .idle` → **your turn** (d) — the agent finished; the ball is in your court.
- `kind == .interactive && status == .busy` → **working now**.
- `kind == .background && state == .working` → **running** (→ "Working now" section).
- `kind == .background && state == .done` → **done** (→ "Recently done").
- Within "Your turn," sort by last-activity desc; recency chip distinguishes *actively waiting* (38m) from *stale* (8d).

**Last prompt (b):** glob `~/.claude/projects/*/<sessionId>.jsonl`; scan from the end for the last record where `type == "user"`, `isMeta != true`, the message content is **not** a `tool_result`, and the text doesn't start with `<` (filters injected/system blocks). Take its text, trim, ellipsise. For background jobs, `name` already holds the job description — use it.
- *Cost control:* the popover reads only the **tail** of each transcript for the last prompt, and caches per `(sessionId, fileSize)` so an unchanged file isn't re-read each 2s poll.

**Active badge count:** interactive `busy` + background `running`.

**Future (out of scope v1):** detect an explicit permission / AskUserQuestion wait (a stronger "needs you NOW" than plain idle) by inspecting the last transcript record. Noted, not built.

---

## 5. Implementation gotchas (from DISCOVERY §5 — must honor)

1. **GUI apps don't inherit shell `PATH`.** `ClaudeCLI` resolves explicitly: `~/.local/bin/claude` (this machine), `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, `$HOME/.claude/local/claude`. Clear error if absent.
2. **Transcript format is internal/version-dependent.** Defensive-parse; never crash on an unexpected record; tolerate missing fields and unknown `type`s.
3. **Buffer the trailing partial line** when reading mid-write; only parse through the last `\n`; keep the remainder.
4. **No push API.** Poll status ~2s; watch transcripts with `DispatchSource.makeFileSystemObjectSource`. No busy-loops.
5. **Privacy.** Transcripts hold full conversation content. Read-only; never transmit; never log bodies.

---

## 6. Build setup decision

**SwiftPM executable** (not an `.xcodeproj`). Rationale: a `MenuBarExtra` + `WindowGroup` SwiftUI app needs no storyboard/asset pipeline, and SwiftPM is fully CLI-buildable (`swift build` / `swift run`) — essential for headless, agent-driven iteration. Set `NSApp.setActivationPolicy(.accessory)` in code (status-bar-only, no Dock icon) instead of an Info.plist `LSUIElement`.
- Min target **macOS 14.0** (`@Observable`, modern `MenuBarExtra`, `.windowResizability`).
- Ship un-sandboxed, Developer ID-signed for personal use (sandbox impractical — reads `~/.claude/`, spawns `claude`).

---

## 7. Milestones (YAGNI-scoped)

- **M0 — Scaffold.** `git init` (done); SwiftPM `AgentMonitor` executable target; `MenuBarExtra` shows a static popover; `.accessory` policy. Record build choice in CLAUDE.md.
- **M1 — Live list.** `ClaudeCLI` + `AgentService` poll the CLI; popover renders the three Triage sections with real sessions, status dots, and the active badge.
- **M2 — Last prompt + transcript.** Last-prompt line in rows (tail-read + cache); `TranscriptStore` resolves via glob and reads history; detail window renders turns; row "Open" works.
- **M3 — Live follow.** Watch `.jsonl` with `DispatchSource`; append turns incrementally; auto-scroll; status pulse animates.
- **M4 — Polish.** Empty/error states, binary-not-found UX, hover metadata reveal, launch-at-login (optional).

## 8. Testing

`TranscriptParser` is pure and unit-tested: feed sample JSONL lines (incl. a malformed line, a partial trailing line, a tool-result `user` record, an unknown `type`) and assert parsed records + that last-prompt extraction picks the right turn. Fixtures lifted from a real `.jsonl`, scrubbed.

## 9. Out of scope (v1)

Controlling sessions (input/kill), remote/multi-machine, sub-agent/workflow drill-in, anything that writes to `~/.claude/`. Read-only observation only.
