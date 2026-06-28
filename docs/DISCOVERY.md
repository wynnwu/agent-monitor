# Discovery: Observing local Claude Code agents

How a separate process can see **what Claude Code sessions are running on this Mac** and **read their conversations**. This is the data foundation for Agent M.

Verified on macOS (Darwin 24.6), Claude Code `2.1.x` (versions `2.1.158` and `2.1.191` installed), June 2026.

> ⚠️ Two surfaces, two stability levels. The CLI command is a supported scripting surface. The on-disk transcript format is **internal and undocumented** — readable, but it can change between Claude Code versions. Treat the file schema as best-effort and defensive-parse everything.

---

## TL;DR

| You want… | Source | Stability |
|-----------|--------|-----------|
| Live list of running sessions + idle/busy status | `claude agents --json [--all]` | Supported (built for scripting) |
| Full conversation content of a session | `~/.claude/projects/<slug>/<sessionId>.jsonl` | Internal format, version-dependent |
| Sub-agent / workflow activity | `…/<sessionId>/subagents/workflows/<wf_id>/*.jsonl` | Internal format |

There is **no live event/IPC API** to subscribe to another session's messages. You **poll** the CLI for status and **watch the transcript file** (FSEvents) for content. The Anthropic API itself is stateless and stores nothing server-side — these are purely local artifacts.

---

## 1. Live status — `claude agents --json`

The supported way to enumerate sessions. Returns a JSON array on stdout, **requires no TTY** (safe to spawn from a GUI app), and exits immediately.

```bash
claude agents --json          # active sessions only
claude agents --json --all    # active + completed/background
claude agents --json --cwd /some/path   # filter to sessions under a path
```

Each entry:

| Field | Type | Notes |
|-------|------|-------|
| `sessionId` | string (UUID) | **Primary key.** Matches the transcript filename. |
| `cwd` | string | Working directory the session was launched in. |
| `kind` | `"interactive"` \| `"background"` | Interactive = a terminal session; background = `claude --bg`. |
| `status` | `"idle"` \| `"busy"` \| `"shell"` \| `"waiting"` | Per-turn activity. **The CLI collapses `shell`/`waiting` into `busy`** — see the registry note below. |
| `state` | `"working"` \| `"blocked"` \| `"done"` \| `"failed"` \| `"stopped"` | **Background only.** Lifecycle. (`blocked` = waiting on you; transient `starting`/`resuming`/`adopted`/`crashed` surface as `working`/`failed`.) |
| `name` | string | AI-generated session slug (e.g. `frenzy-tile-rounding-fix`). May be absent early in a session. |
| `pid` | number | OS process id. Absent for a completed background entry. |
| `id` | string (short) | **Background only.** 8-char id used by `claude agents` management. |
| `startedAt` | number | Epoch **milliseconds**. |

Field availability differs by `kind` (verified):

- **interactive**: `cwd, kind, name, pid, sessionId, startedAt, status`
- **background**: above **plus** `id`, `state`

Mental model:
- `status` answers *"is it thinking right now?"* — use it for the live activity dot.
- `state` answers *"is this background job still alive / does it need me?"* — gray out finished background agents (`done`/`failed`/`stopped`); surface `blocked`.

### ⚠️ The CLI over-reports `busy` — cross-reference the per-PID registry

The interactive status vocabulary is exactly `busy · shell · idle · waiting` (verified against the
CLI binary's own validation set, `s9p=["busy","shell","idle","waiting"]`). But `claude agents --json`
**collapses `shell` and `waiting` into `busy`** — so a session sitting at a shell (done, idle) or
blocked on a permission prompt both report `busy`, and naively mapping `busy → working` mislabels them.

The finer truth lives in the **per-PID registry**: `~/.claude/sessions/<pid>.json`, one file per live
`claude` process, written in near-real-time:

```json
{ "pid": 14455, "sessionId": "81d75e8b-…", "cwd": "…", "kind": "interactive",
  "status": "shell", "waitingFor": null, "updatedAt": 1782…, "statusUpdatedAt": 1782…,
  "entrypoint": "cli", "bridgeSessionId": null }
```

Its `status` carries the un-collapsed value. Resolve a session's status by reading
`sessions/<pid>.json` and **preferring its `status`** over the CLI's (guard PID reuse by requiring
`sessionId` to match; fall back to the CLI value if the file is absent/mismatched). `shell` is a
sub-state of idle; `waiting` (often with a `waitingFor` reason) is the authoritative "needs you" signal.

**Correct bucket mapping** (what `AgentMCore/SessionGrouping.swift` implements):

| Source | Value | Bucket |
|--------|-------|--------|
| interactive `status` | `busy` | **Working** — unless the transcript shows a completed turn awaiting you (see below) |
| interactive `status` | `shell` | **Idle** (at/after a shell command; not processing) |
| interactive `status` | `idle` | **Idle**, or *Waiting for you* if the last turn hands back to you (see below) |
| interactive `status` | `waiting` | **Waiting for you** (permission prompt / input request) |
| background `state` | `working` | **Working** |
| background `state` | `blocked` | **Waiting for you** |
| background `state` | `done` / `failed` / `stopped` | **Idle** |

**"Hands back to you" / overriding a stale `busy`.** `status` can lag — a session that finished
its turn and is awaiting your reply sometimes still reports `busy`. So *Waiting for you* is also
inferred from the transcript: the last assistant turn is **complete** (`message.stop_reason ==
"end_turn"`, with no newer user reply or pending tool) **and** its closing text solicits a response —
a trailing `?` or a hand-off sign-off ("let me know", "want me to…", "I'll wait for your word"). The
`end_turn` gate is what makes this safe to trust over a stale `busy`: a session that's genuinely
mid-work stopped for a tool (`stop_reason == "tool_use"`) or hasn't finished, so it never matches.

---

## 2. Full conversation — the transcript JSONL

Every session is persisted, appended in **near-real-time** (one record per message / tool result / state change), at:

```
~/.claude/projects/<slug>/<sessionId>.jsonl
```

### Resolving the path — glob by `sessionId`, do NOT rebuild the slug

`<slug>` is the `cwd` with `/`, spaces, and other non-alphanumeric path characters replaced by `-`:

```
/Users/you/Code/Acme/web-client
→ -Users-you-Code-Acme-web-client
```

(Runs of special chars collapse to multiple dashes — e.g. a literal ` - ` in a folder name becomes `---`.) The exact transform is undocumented, so **don't reconstruct it**. `sessionId` is a globally-unique UUID, so just glob:

```bash
ls ~/.claude/projects/*/<sessionId>.jsonl    # exactly one match
```

This is robust across any cwd weirdness and is the approach the app should use.

### Record shape

Each line is one JSON object. Observed top-level keys:

```
type, message, timestamp, uuid, parentUuid, sessionId, cwd, gitBranch,
version, userType, isMeta, isSidechain, requestId, messageId, promptId,
toolUseResult, attachment, snapshot, slug, aiTitle, mode, permissionMode, …
```

Observed `type` values:

| `type` | Meaning |
|--------|---------|
| `user` | A user turn (or a tool result fed back as a user message). |
| `assistant` | An assistant turn. `message` holds the Anthropic-style message (role + content blocks: text / tool_use). |
| `attachment` | Attached context (files, command output). |
| `file-history-snapshot` | Editor file-state snapshot for undo/history. |
| `last-prompt` | Bookkeeping for the most recent prompt. |
| `mode` / `permission-mode` | Session mode + permission-mode changes. |
| `ai-title` | The generated session title/slug. |

For rendering a conversation, the load-bearing records are `type: "user"` and `type: "assistant"`; their `message` field is the chat content. Tool calls appear as `tool_use` blocks inside assistant messages; tool results arrive as `toolUseResult` / subsequent user records. Records form a tree via `uuid` / `parentUuid` (note `isSidechain` flags sub-agent branches).

### Following it live

The file is append-only, so:
- **Watch** with `DispatchSource.makeFileSystemObjectSource` (or FSEvents) on the file for `.write`/`.extend` events.
- Keep a byte offset; on change, read **only the appended bytes** and split on `\n`.
- **Buffer the trailing partial line** — a read mid-write can land in the middle of a JSON object. Only parse a line once you've seen its terminating newline.
- An in-memory turn that is still streaming is **not on disk yet**; it appears once the record is flushed. So "live" = sub-second-to-seconds lag, not instantaneous.

---

## 3. Sub-agents & workflows

When a session spawns sub-agents or runs a Workflow, their transcripts nest under the parent session:

```
~/.claude/projects/<slug>/<sessionId>/subagents/workflows/<wf_id>/
    journal.jsonl          # workflow orchestration journal
    agent-<id>.jsonl       # one transcript per spawned agent
```

Same JSONL conventions. Useful later for a "drill into what the sub-agents are doing" view; out of scope for the first milestone.

---

## 4. Practical recipe (what the app does)

```
                 every ~2s                        on file change (FSEvents)
 ┌────────────────────────────┐        ┌──────────────────────────────────────┐
 │ claude agents --json --all │        │ ~/.claude/projects/*/<sessionId>.jsonl │
 │  → [{sessionId,status,…}]  │        │  → append-only conversation records    │
 └─────────────┬──────────────┘        └────────────────────┬───────────────────┘
               │ session list + status                       │ selected session content
               ▼                                             ▼
        Menu-bar popover  ───────── user clicks "Open" ──────►  Detail window
        (glanceable dots)                                       (transcript viewer)
```

1. Poll `claude agents --json --all` on a timer → drives the menu-bar list and the busy/idle dots.
2. When the user selects a session, glob `~/.claude/projects/*/<sessionId>.jsonl` → resolve the transcript.
3. Read it once for history, then watch for appends and parse incrementally.
4. Render `user`/`assistant` records in the detail window.

---

## 5. Gotchas & caveats (read before coding)

- **GUI apps don't inherit your shell `PATH`.** A bundled `.app` launched from Finder won't find `claude` on `PATH`. Resolve the binary explicitly: check `~/.local/bin/claude`, `/usr/local/bin/claude`, `/opt/homebrew/bin/claude`, and `$HOME/.claude/local/claude`, or read it from a setting. (On this machine it's `~/.local/bin/claude`.)
- **Internal format risk.** The transcript schema is undocumented and changed shape across `2.1.x`. Defensive-parse: tolerate unknown `type`s, missing fields, and schema drift. Pin nothing.
- **Partial trailing line** when reading during a write — buffer until newline (see §2).
- **No push API** — you poll status and watch files. Budget a sensible poll interval (2–3s) to stay light.
- **Privacy / scope** — transcripts contain full conversation content (and possibly secrets pasted into sessions). This is a *local, personal* tool reading the current user's own files. Don't transmit transcript content anywhere.
- **Sandboxing** — reading `~/.claude/` (outside an App Sandbox container) and spawning a process means a Mac App Store sandbox is impractical. Ship un-sandboxed, Developer ID–signed, for personal use. See CLAUDE.md §Sandboxing.
- **Multiple installed versions** — `--bg-spare`/`--bg-pty-host` helper processes and a `claude daemon run` process also show up in `ps`; ignore those. Use `claude agents --json` as the source of truth for "sessions," not raw `ps`.

---

## Appendix: reference commands

```bash
# Live session list (pretty)
claude agents --json --all | jq -r '.[] | "\(.status)\t\(.kind)\t\(.name // "—")\t\(.cwd)"'

# Resolve a session's transcript
ls ~/.claude/projects/*/<sessionId>.jsonl

# Tail a session's conversation, assistant text only
tail -f "$(ls ~/.claude/projects/*/<sessionId>.jsonl)" \
  | jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text'
```

See `scripts/agent-snapshot.sh` for a small working reference implementation of the core data access.
