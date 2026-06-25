# Agent Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu-bar app that shows every local Claude Code session — directory, last prompt, status, and whether it's waiting on you — and opens any session's transcript in a detail window.

**Architecture:** A pure, fully-tested `AgentMonitorCore` library (models, JSONL parser, status-derivation, formatting) plus a thin `AgentMonitor` SwiftUI executable that does IO (spawning `claude`, reading/watching `~/.claude/projects/*.jsonl`) and renders the UI. The popover follows the "Triage" design (Your turn → Working now → Recently done). State via `@Observable`.

**Tech Stack:** Swift 6 / SwiftPM executable, SwiftUI (`MenuBarExtra` + `WindowGroup`), `Foundation.Process`, `DispatchSource` file watching, XCTest. No third-party dependencies.

## Global Constraints

- **Min target:** macOS 14.0. (Toolchain present: Swift 6.2.4, Xcode 26.3, macOS 15.7.)
- **No third-party dependencies.** Apple frameworks only.
- **Read-only.** Never write to `~/.claude/`. Never transmit or log transcript bodies.
- **`claude` binary resolution** (GUI apps don't inherit shell PATH) — search in order: `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, `$HOME/.claude/local/claude`. On this machine it's `~/.local/bin/claude`.
- **Defensive parsing.** Tolerate unknown `type`s, missing fields, schema drift, and partial trailing lines. Never crash on an unexpected record.
- **Poll cadence ~2s** for status; **watch** transcripts with `DispatchSource` (no busy-loops).
- **Status-bar only:** `NSApp.setActivationPolicy(.accessory)` — no Dock icon.
- **Visual reference for the popover/detail window:** `scratchpad/proposal-a-triage.html` (the approved "Triage" mockup). Match its hierarchy, spacing, and palette (your-turn amber `#F5A623`, working green `#30D158`, running blue `#0A84FF`, done gray `#8E8E93`; popover material `rgba(28,28,30,0.72)` + blur).
- **Status buckets** (verbatim from spec §4):
  - interactive + idle → **your turn**
  - interactive + busy → **working now**
  - background + working → **running** (Working now section)
  - background + done → **done** (Recently done section)
- **Spec:** `docs/superpowers/specs/2026-06-25-agent-monitor-design.md`.

---

## File Structure

```
Package.swift
Sources/
  AgentMonitorCore/                 ← pure, no SwiftUI, fully unit-tested
    AgentSession.swift              ← wire model + Codable + display computed props
    SessionGrouping.swift           ← StatusBucket, SessionGroups, groupSessions()
    RelativeTime.swift              ← relativeTime(from:now:)
    TranscriptRecord.swift          ← rendered record type
    TranscriptParser.swift          ← parseLine(), lastUserPrompt()
    BinaryResolver.swift            ← resolveClaudeBinary(candidates:exists:)
  AgentMonitor/                     ← executable: IO + SwiftUI
    AgentMonitorApp.swift           ← @main, MenuBarExtra + WindowGroup, .accessory
    Services/
      ClaudeCLI.swift               ← spawn `claude agents --json --all`, decode
      TranscriptIO.swift            ← glob path, tail-read last prompt, file mtime
      AgentService.swift            ← @Observable, 2s poll loop → SessionGroups + lastPrompts
      TranscriptStore.swift         ← @Observable, history read + DispatchSource watch
    Views/
      SessionListView.swift         ← popover: three TriageSections
      SessionRowView.swift          ← one row (dot, folder, prompt, time, branch chip)
      TranscriptView.swift          ← detail window
      Theme.swift                   ← colors, materials, shared modifiers
Tests/
  AgentMonitorCoreTests/
    AgentSessionTests.swift
    SessionGroupingTests.swift
    RelativeTimeTests.swift
    TranscriptParserTests.swift
    BinaryResolverTests.swift
    Fixtures/                       ← scrubbed sample .jsonl lines
```

---

### Task 1: SwiftPM scaffold + menu-bar shell (M0)

**Files:**
- Create: `Package.swift`
- Create: `Sources/AgentMonitor/AgentMonitorApp.swift`
- Create: `Sources/AgentMonitorCore/Placeholder.swift` (temporary, so the library target compiles)

**Interfaces:**
- Produces: an executable `AgentMonitor` that launches as a status-bar app showing a static popover; a library target `AgentMonitorCore` other tasks add to.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AgentMonitorCore"),
        .executableTarget(
            name: "AgentMonitor",
            dependencies: ["AgentMonitorCore"]
        ),
        .testTarget(
            name: "AgentMonitorCoreTests",
            dependencies: ["AgentMonitorCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Add a temporary placeholder so the library compiles**

`Sources/AgentMonitorCore/Placeholder.swift`:
```swift
public enum AgentMonitorCore {
    public static let version = "0.0.1"
}
```

- [ ] **Step 3: Write the app shell**

`Sources/AgentMonitor/AgentMonitorApp.swift`:
```swift
import SwiftUI

@main
struct AgentMonitorApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.accessory) // status-bar only, no Dock icon
    }

    var body: some Scene {
        MenuBarExtra("Agent Monitor", systemImage: "dot.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Agent Monitor").font(.headline)
                Text("No sessions yet.").foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 380)
        }
        .menuBarExtraStyle(.window) // popover-style, allows custom layout
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 5: Smoke-run (manual, brief)**

Run: `swift run AgentMonitor &` then after ~3s `kill %1`
Expected: a menu-bar icon appears (top-right), no Dock icon, no crash. Clicking shows the static popover. (In a headless context, just confirm `swift run` launches without error before killing.)

- [ ] **Step 6: Record build choice + commit**

Append to `CLAUDE.md` under "Build & run": "**Decision (M0):** SwiftPM executable (no .xcodeproj). Build `swift build`; run `swift run AgentMonitor`; test `swift test`."
```bash
git add -A && git commit -m "feat(m0): SwiftPM scaffold + static menu-bar popover"
```

---

### Task 2: AgentSession model + defensive decoding (M1)

**Files:**
- Create: `Sources/AgentMonitorCore/AgentSession.swift`
- Test: `Tests/AgentMonitorCoreTests/AgentSessionTests.swift`
- Delete: `Sources/AgentMonitorCore/Placeholder.swift` (replaced by real code)

**Interfaces:**
- Produces:
  - `struct AgentSession: Identifiable, Codable, Hashable, Sendable` with `id: String { sessionId }`, stored `sessionId, cwd: String`, `kind: Kind`, optional `status: Status?`, `state: State?`, `name: String?`, `pid: Int?`, `startedAt: Double?`.
  - nested `enum Kind: String { case interactive, background }`, `Status { case idle, busy }`, `State { case working, done }`.
  - computed `var folder: String`, `var parentPath: String` (parent dir, home abbreviated to `~`).
  - `static func decodeArray(from data: Data) -> [AgentSession]` — skips entries missing required fields, never throws.

- [ ] **Step 1: Write the failing tests**

`Tests/AgentMonitorCoreTests/AgentSessionTests.swift`:
```swift
import XCTest
@testable import AgentMonitorCore

final class AgentSessionTests: XCTestCase {
    func test_decodes_interactive_entry() {
        let json = """
        [{"sessionId":"abc","cwd":"/Users/x/Code/demo-app","kind":"interactive","status":"idle","name":null,"pid":42,"startedAt":1780120552235}]
        """.data(using: .utf8)!
        let s = AgentSession.decodeArray(from: json)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].sessionId, "abc")
        XCTAssertEqual(s[0].kind, .interactive)
        XCTAssertEqual(s[0].status, .idle)
        XCTAssertNil(s[0].state)
        XCTAssertEqual(s[0].folder, "demo-app")
    }

    func test_decodes_background_with_state_and_id() {
        let json = """
        [{"sessionId":"bg1","cwd":"/Users/x/p","kind":"background","status":"idle","state":"working","id":"bg1abcd","name":"job","startedAt":1.0}]
        """.data(using: .utf8)!
        let s = AgentSession.decodeArray(from: json)
        XCTAssertEqual(s[0].kind, .background)
        XCTAssertEqual(s[0].state, .working)
    }

    func test_skips_entry_missing_required_field_but_keeps_others() {
        let json = """
        [{"cwd":"/no/sessionId","kind":"interactive"},
         {"sessionId":"ok","cwd":"/Users/x/Code/app","kind":"interactive"}]
        """.data(using: .utf8)!
        let s = AgentSession.decodeArray(from: json)
        XCTAssertEqual(s.map(\.sessionId), ["ok"])
    }

    func test_tolerates_unknown_kind_and_garbage() {
        XCTAssertEqual(AgentSession.decodeArray(from: Data("not json".utf8)).count, 0)
        let weird = """
        [{"sessionId":"z","cwd":"/p","kind":"spaceship"}]
        """.data(using: .utf8)!
        XCTAssertEqual(AgentSession.decodeArray(from: weird).count, 0) // unknown kind dropped
    }

    func test_parentPath_abbreviates_home() {
        let json = #"[{"sessionId":"a","cwd":"\#(NSHomeDirectory())/Code/x","kind":"interactive"}]"#.data(using: .utf8)!
        let s = AgentSession.decodeArray(from: json)
        XCTAssertEqual(s[0].parentPath, "~/Code")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentSessionTests`
Expected: FAIL — `AgentSession` not found.

- [ ] **Step 3: Implement the model**

Delete `Sources/AgentMonitorCore/Placeholder.swift`. Create `Sources/AgentMonitorCore/AgentSession.swift`:
```swift
import Foundation

public struct AgentSession: Identifiable, Codable, Hashable, Sendable {
    public var id: String { sessionId }
    public let sessionId: String
    public let cwd: String
    public let kind: Kind
    public let status: Status?
    public let state: State?
    public let name: String?
    public let pid: Int?
    public let startedAt: Double?

    public enum Kind: String, Codable, Sendable { case interactive, background }
    public enum Status: String, Codable, Sendable { case idle, busy }
    public enum State: String, Codable, Sendable { case working, done }

    public var folder: String { URL(fileURLWithPath: cwd).lastPathComponent }

    public var parentPath: String {
        let parent = URL(fileURLWithPath: cwd).deletingLastPathComponent().path
        let home = NSHomeDirectory()
        if parent == home { return "~" }
        if parent.hasPrefix(home + "/") { return "~" + parent.dropFirst(home.count) }
        return parent
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, cwd, kind, status, state, name, pid, startedAt
    }

    public init(sessionId: String, cwd: String, kind: Kind, status: Status? = nil,
                state: State? = nil, name: String? = nil, pid: Int? = nil, startedAt: Double? = nil) {
        self.sessionId = sessionId; self.cwd = cwd; self.kind = kind
        self.status = status; self.state = state; self.name = name
        self.pid = pid; self.startedAt = startedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        cwd       = try c.decode(String.self, forKey: .cwd)
        kind      = try c.decode(Kind.self, forKey: .kind)         // unknown kind → throws → dropped
        status    = try? c.decodeIfPresent(Status.self, forKey: .status) ?? nil
        state     = try? c.decodeIfPresent(State.self, forKey: .state) ?? nil
        name      = try? c.decodeIfPresent(String.self, forKey: .name) ?? nil
        pid       = try? c.decodeIfPresent(Int.self, forKey: .pid) ?? nil
        startedAt = try? c.decodeIfPresent(Double.self, forKey: .startedAt) ?? nil
    }

    /// Decode a JSON array, dropping any entry that fails (missing/invalid required field).
    /// Never throws — returns whatever decoded cleanly.
    public static func decodeArray(from data: Data) -> [AgentSession] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        let decoder = JSONDecoder()
        return raw.compactMap { element in
            guard let objData = try? JSONSerialization.data(withJSONObject: element) else { return nil }
            return try? decoder.decode(AgentSession.self, from: objData)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AgentSessionTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(core): AgentSession model with defensive array decoding"
```

---

### Task 3: Relative-time formatting (M1)

**Files:**
- Create: `Sources/AgentMonitorCore/RelativeTime.swift`
- Test: `Tests/AgentMonitorCoreTests/RelativeTimeTests.swift`

**Interfaces:**
- Produces: `public func relativeTime(from date: Date, now: Date) -> String` → `"now"`, `"38m"`, `"3h"`, `"8d"`, `"18d"`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AgentMonitorCore

final class RelativeTimeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    func t(_ secondsAgo: TimeInterval) -> String { relativeTime(from: now.addingTimeInterval(-secondsAgo), now: now) }
    func test_now_under_60s()    { XCTAssertEqual(t(30), "now") }
    func test_minutes()          { XCTAssertEqual(t(38*60), "38m") }
    func test_hours()            { XCTAssertEqual(t(3*3600), "3h") }
    func test_days()             { XCTAssertEqual(t(8*86400), "8d") }
    func test_future_clamps_now(){ XCTAssertEqual(relativeTime(from: now.addingTimeInterval(120), now: now), "now") }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter RelativeTimeTests` — Expected: FAIL (not defined).

- [ ] **Step 3: Implement**

```swift
import Foundation

public func relativeTime(from date: Date, now: Date) -> String {
    let s = now.timeIntervalSince(date)
    if s < 60 { return "now" }
    if s < 3600 { return "\(Int(s / 60))m" }
    if s < 86400 { return "\(Int(s / 3600))h" }
    return "\(Int(s / 86400))d"
}
```

- [ ] **Step 4: Run to verify pass** — Run: `swift test --filter RelativeTimeTests` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(core): relativeTime formatter"
```

---

### Task 4: Session grouping into Triage sections (M1)

**Files:**
- Create: `Sources/AgentMonitorCore/SessionGrouping.swift`
- Test: `Tests/AgentMonitorCoreTests/SessionGroupingTests.swift`

**Interfaces:**
- Consumes: `AgentSession` (Task 2).
- Produces:
  - `public enum StatusBucket: Sendable { case yourTurn, working, recentlyDone }`
  - `public func bucket(for s: AgentSession) -> StatusBucket`
  - `public struct SessionGroups: Sendable { public let yourTurn, working, recentlyDone: [AgentSession]; public let activeBadge: Int }`
  - `public func groupSessions(_ sessions: [AgentSession], lastActivity: [String: Date], now: Date) -> SessionGroups` — `yourTurn` sorted by `lastActivity[sessionId] ?? startedAt` desc; `activeBadge` = count of interactive-busy + background-working.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AgentMonitorCore

final class SessionGroupingTests: XCTestCase {
    func mk(_ id: String, _ kind: AgentSession.Kind, status: AgentSession.Status? = nil,
            state: AgentSession.State? = nil) -> AgentSession {
        AgentSession(sessionId: id, cwd: "/p/\(id)", kind: kind, status: status, state: state)
    }

    func test_buckets() {
        XCTAssertEqual(bucket(for: mk("a", .interactive, status: .idle)), .yourTurn)
        XCTAssertEqual(bucket(for: mk("b", .interactive, status: .busy)), .working)
        XCTAssertEqual(bucket(for: mk("c", .background, state: .working)), .working)
        XCTAssertEqual(bucket(for: mk("d", .background, state: .done)), .recentlyDone)
    }

    func test_groups_and_badge() {
        let sessions = [
            mk("idle1", .interactive, status: .idle),
            mk("busy1", .interactive, status: .busy),
            mk("bgwork", .background, state: .working),
            mk("bgdone", .background, state: .done),
        ]
        let g = groupSessions(sessions, lastActivity: [:], now: Date())
        XCTAssertEqual(g.yourTurn.map(\.sessionId), ["idle1"])
        XCTAssertEqual(Set(g.working.map(\.sessionId)), ["busy1", "bgwork"])
        XCTAssertEqual(g.recentlyDone.map(\.sessionId), ["bgdone"])
        XCTAssertEqual(g.activeBadge, 2) // busy1 + bgwork
    }

    func test_yourTurn_sorted_recent_first() {
        let now = Date(timeIntervalSince1970: 1000)
        let a = mk("old", .interactive, status: .idle)
        let b = mk("new", .interactive, status: .idle)
        let g = groupSessions([a, b], lastActivity: [
            "old": now.addingTimeInterval(-1000),
            "new": now.addingTimeInterval(-10),
        ], now: now)
        XCTAssertEqual(g.yourTurn.map(\.sessionId), ["new", "old"])
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter SessionGroupingTests` — FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum StatusBucket: Sendable { case yourTurn, working, recentlyDone }

public func bucket(for s: AgentSession) -> StatusBucket {
    switch s.kind {
    case .interactive:
        return s.status == .busy ? .working : .yourTurn
    case .background:
        return s.state == .working ? .working : .recentlyDone
    }
}

public struct SessionGroups: Sendable {
    public let yourTurn: [AgentSession]
    public let working: [AgentSession]
    public let recentlyDone: [AgentSession]
    public let activeBadge: Int
    public init(yourTurn: [AgentSession], working: [AgentSession], recentlyDone: [AgentSession], activeBadge: Int) {
        self.yourTurn = yourTurn; self.working = working
        self.recentlyDone = recentlyDone; self.activeBadge = activeBadge
    }
}

public func groupSessions(_ sessions: [AgentSession], lastActivity: [String: Date], now: Date) -> SessionGroups {
    func activity(_ s: AgentSession) -> Date {
        lastActivity[s.sessionId] ?? s.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
    }
    var yt: [AgentSession] = [], wk: [AgentSession] = [], rd: [AgentSession] = []
    for s in sessions {
        switch bucket(for: s) {
        case .yourTurn: yt.append(s)
        case .working: wk.append(s)
        case .recentlyDone: rd.append(s)
        }
    }
    yt.sort { activity($0) > activity($1) }
    rd.sort { activity($0) > activity($1) }
    let badge = sessions.filter {
        ($0.kind == .interactive && $0.status == .busy) || ($0.kind == .background && $0.state == .working)
    }.count
    return SessionGroups(yourTurn: yt, working: wk, recentlyDone: rd, activeBadge: badge)
}
```

- [ ] **Step 4: Run to verify pass** — `swift test --filter SessionGroupingTests` — PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(core): Triage grouping + active badge count"
```

---

### Task 5: Claude binary resolver (M1)

**Files:**
- Create: `Sources/AgentMonitorCore/BinaryResolver.swift`
- Test: `Tests/AgentMonitorCoreTests/BinaryResolverTests.swift`

**Interfaces:**
- Produces:
  - `public func defaultClaudeCandidates(home: String) -> [String]` → the four ordered paths.
  - `public func resolveClaudeBinary(candidates: [String], exists: (String) -> Bool) -> String?` — first existing candidate, else nil.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AgentMonitorCore

final class BinaryResolverTests: XCTestCase {
    func test_candidate_order() {
        let c = defaultClaudeCandidates(home: "/Users/x")
        XCTAssertEqual(c.first, "/Users/x/.local/bin/claude")
        XCTAssertTrue(c.contains("/opt/homebrew/bin/claude"))
        XCTAssertTrue(c.contains("/usr/local/bin/claude"))
        XCTAssertTrue(c.contains("/Users/x/.claude/local/claude"))
    }
    func test_picks_first_existing() {
        let present: Set<String> = ["/opt/homebrew/bin/claude"]
        let r = resolveClaudeBinary(candidates: defaultClaudeCandidates(home: "/Users/x")) { present.contains($0) }
        XCTAssertEqual(r, "/opt/homebrew/bin/claude")
    }
    func test_nil_when_none() {
        XCTAssertNil(resolveClaudeBinary(candidates: ["/a", "/b"]) { _ in false })
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter BinaryResolverTests` — FAIL.

- [ ] **Step 3: Implement**

```swift
public func defaultClaudeCandidates(home: String) -> [String] {
    ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
}

public func resolveClaudeBinary(candidates: [String], exists: (String) -> Bool) -> String? {
    candidates.first(where: exists)
}
```

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(core): claude binary resolver"
```

---

### Task 6: ClaudeCLI service — spawn + decode (M1)

**Files:**
- Create: `Sources/AgentMonitor/Services/ClaudeCLI.swift`

**Interfaces:**
- Consumes: `defaultClaudeCandidates`, `resolveClaudeBinary`, `AgentSession.decodeArray` (Core).
- Produces:
  - `enum ClaudeCLIError: Error { case binaryNotFound([String]) }`
  - `struct ClaudeCLI: Sendable { func fetchSessions() async throws -> [AgentSession] }` — resolves binary, runs `agents --json --all` TTY-free, returns decoded sessions (empty array on non-zero exit but valid-empty output; throws `binaryNotFound` if no binary).

- [ ] **Step 1: Implement (verified by build + live smoke since it spawns a real process)**

`Sources/AgentMonitor/Services/ClaudeCLI.swift`:
```swift
import Foundation
import AgentMonitorCore

enum ClaudeCLIError: Error, LocalizedError {
    case binaryNotFound([String])
    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let paths):
            return "Couldn't find the `claude` binary. Looked in:\n" + paths.joined(separator: "\n")
        }
    }
}

struct ClaudeCLI: Sendable {
    func resolveBinary() throws -> String {
        let candidates = defaultClaudeCandidates(home: NSHomeDirectory())
        let fm = FileManager.default
        guard let path = resolveClaudeBinary(candidates: candidates, exists: { fm.isExecutableFile(atPath: $0) })
        else { throw ClaudeCLIError.binaryNotFound(candidates) }
        return path
    }

    func fetchSessions() async throws -> [AgentSession] {
        let binary = try resolveBinary()
        let data = try await run(binary, ["agents", "--json", "--all"])
        return AgentSession.decodeArray(from: data)
    }

    private func run(_ launchPath: String, _ args: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: launchPath)
            proc.arguments = args
            let out = Pipe(); proc.standardOutput = out
            proc.standardError = Pipe()
            // Minimal env; PATH is irrelevant since we use an absolute launch path.
            proc.environment = ["HOME": NSHomeDirectory()]
            do {
                try proc.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                cont.resume(returning: data)
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
```

- [ ] **Step 2: Build** — Run: `swift build` — Expected: `Build complete!`

- [ ] **Step 3: Live smoke (manual, depends on real sessions)**

Add a temporary `@main`-free check or use a scratch test target is overkill; instead verify via the running app in Task 8. For now, confirm compilation. (Optional manual: a throwaway `swift -e`-style check is not available for package targets; rely on Task 8's live list.)

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(app): ClaudeCLI spawns `claude agents --json` and decodes"
```

---

### Task 7: TranscriptIO — glob path, file mtime, tail last-prompt (M2)

This task pairs pure extraction (TDD in Core) with file IO (in the executable).

**Files:**
- Create: `Sources/AgentMonitorCore/TranscriptParser.swift` (parseLine + lastUserPrompt)
- Create: `Sources/AgentMonitorCore/TranscriptRecord.swift`
- Create: `Sources/AgentMonitor/Services/TranscriptIO.swift`
- Test: `Tests/AgentMonitorCoreTests/TranscriptParserTests.swift`
- Create fixtures: `Tests/AgentMonitorCoreTests/Fixtures/sample.jsonl`

**Interfaces:**
- Produces (Core):
  - `public struct TranscriptRecord: Identifiable, Hashable, Sendable { public let id: String; public let role: Role; public let text: String; public let toolUses: [String]; public let isToolResult: Bool; public let isMeta: Bool; public let timestamp: Date?; public enum Role: String, Sendable { case user, assistant, system, other } }`
  - `public enum TranscriptParser { public static func parseLine(_ line: String) -> TranscriptRecord?; public static func lastUserPrompt(in lines: [String]) -> String? }`
- Produces (executable):
  - `enum TranscriptIO { static func transcriptPath(forSessionID: String) -> String?; static func lastModified(_ path: String) -> Date?; static func lastPrompt(forSessionID: String) -> String? }`

- [ ] **Step 1: Create fixture** `Tests/AgentMonitorCoreTests/Fixtures/sample.jsonl` (scrubbed real lines + edge cases; the last newline omitted to simulate a partial trailing line):

```
{"type":"user","isMeta":true,"message":{"role":"user","content":"<system-reminder>ignore me</system-reminder>"},"timestamp":"2026-06-25T08:00:00.000Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it."},{"type":"tool_use","name":"Bash"}]},"timestamp":"2026-06-25T08:00:01.000Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]},"timestamp":"2026-06-25T08:00:02.000Z"}
{"type":"user","message":{"role":"user","content":"Add a LICENSE file to the repo."},"timestamp":"2026-06-25T08:00:03.000Z"}
{"type":"file-history-snapshot","snapshot":{}}
not even json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done."}]},"timestamp":"2026-06-25T08:00:04.000Z"}
{"type":"user","message":{"role":"user","content":"partial line with no newline
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import AgentMonitorCore

final class TranscriptParserTests: XCTestCase {
    func lines() throws -> [String] {
        let url = Bundle.module.url(forResource: "sample", withExtension: "jsonl", subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
    }

    func test_parses_assistant_text_and_tooluse() throws {
        let recs = try lines().compactMap(TranscriptParser.parseLine)
        let asst = recs.first { $0.role == .assistant }!
        XCTAssertTrue(asst.text.contains("On it."))
        XCTAssertEqual(asst.toolUses, ["Bash"])
    }

    func test_marks_tool_result_user() throws {
        let recs = try lines().compactMap(TranscriptParser.parseLine)
        XCTAssertTrue(recs.contains { $0.role == .user && $0.isToolResult })
    }

    func test_skips_garbage_and_partial() {
        XCTAssertNil(TranscriptParser.parseLine("not even json"))
        XCTAssertNil(TranscriptParser.parseLine(""))
        XCTAssertNil(TranscriptParser.parseLine(#"{"type":"user","message":{"role":"user","content":"partial line with no newline"#))
    }

    func test_lastUserPrompt_picks_real_prompt() throws {
        // Skips: meta, the `<system-reminder>`, the tool_result user, and the unterminated partial line.
        XCTAssertEqual(TranscriptParser.lastUserPrompt(in: try lines()), "Add a LICENSE file to the repo.")
    }

    func test_lastUserPrompt_nil_when_none() {
        XCTAssertNil(TranscriptParser.lastUserPrompt(in: ["garbage", ""]))
    }
}
```

- [ ] **Step 3: Run to verify fail** — `swift test --filter TranscriptParserTests` — FAIL.

- [ ] **Step 4: Implement `TranscriptRecord.swift`**

```swift
import Foundation

public struct TranscriptRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let role: Role
    public let text: String
    public let toolUses: [String]
    public let isToolResult: Bool
    public let isMeta: Bool
    public let timestamp: Date?
    public enum Role: String, Sendable { case user, assistant, system, other }

    public init(id: String, role: Role, text: String, toolUses: [String],
                isToolResult: Bool, isMeta: Bool, timestamp: Date?) {
        self.id = id; self.role = role; self.text = text; self.toolUses = toolUses
        self.isToolResult = isToolResult; self.isMeta = isMeta; self.timestamp = timestamp
    }
}
```

- [ ] **Step 5: Implement `TranscriptParser.swift`**

```swift
import Foundation

public enum TranscriptParser {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func parseLine(_ line: String) -> TranscriptRecord? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let type = obj["type"] as? String ?? "other"
        let role: TranscriptRecord.Role
        switch type {
        case "user": role = .user
        case "assistant": role = .assistant
        default: role = .other
        }
        let isMeta = obj["isMeta"] as? Bool ?? false
        let ts = (obj["timestamp"] as? String).flatMap { iso.date(from: $0) }
        let id = obj["uuid"] as? String ?? UUID().uuidString

        var text = ""
        var toolUses: [String] = []
        var isToolResult = false
        if let message = obj["message"] as? [String: Any] {
            let content = message["content"]
            if let s = content as? String {
                text = s
            } else if let blocks = content as? [[String: Any]] {
                for b in blocks {
                    switch b["type"] as? String {
                    case "text": text += (b["text"] as? String ?? "")
                    case "tool_use": if let n = b["name"] as? String { toolUses.append(n) }
                    case "tool_result": isToolResult = true
                    default: break
                    }
                }
            }
        }
        return TranscriptRecord(id: id, role: role, text: text, toolUses: toolUses,
                                isToolResult: isToolResult, isMeta: isMeta, timestamp: ts)
    }

    /// The last genuine user prompt: a user turn that isn't meta, isn't a tool result,
    /// and isn't an injected `<...>` block. Scans from the end.
    public static func lastUserPrompt(in lines: [String]) -> String? {
        for line in lines.reversed() {
            guard let r = parseLine(line) else { continue }
            let t = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if r.role == .user, !r.isMeta, !r.isToolResult, !t.isEmpty, !t.hasPrefix("<") {
                return t
            }
        }
        return nil
    }
}
```

- [ ] **Step 6: Run to verify pass** — `swift test --filter TranscriptParserTests` — PASS (5 tests).

- [ ] **Step 7: Implement `TranscriptIO.swift`** (file IO; verified live in Task 8)

```swift
import Foundation
import AgentMonitorCore

enum TranscriptIO {
    static var projectsDir: String { "\(NSHomeDirectory())/.claude/projects" }

    /// Glob by sessionId — do NOT reconstruct the slug (DISCOVERY §2).
    static func transcriptPath(forSessionID id: String) -> String? {
        let matches = (try? FileManager.default.contentsOfDirectory(atPath: projectsDir)) ?? []
        for slug in matches {
            let candidate = "\(projectsDir)/\(slug)/\(id).jsonl"
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    static func lastModified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Read the tail of the transcript and extract the last real user prompt.
    /// Reads at most `maxBytes` from the end to stay cheap on huge transcripts.
    static func lastPrompt(forSessionID id: String, maxBytes: Int = 64_000) -> String? {
        guard let path = transcriptPath(forSessionID: id),
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let str = String(data: data, encoding: .utf8) else { return nil }
        // Drop a possibly-truncated first line when we didn't start at byte 0.
        var lines = str.components(separatedBy: "\n")
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return TranscriptParser.lastUserPrompt(in: lines)
    }
}
```

- [ ] **Step 8: Build + commit**

Run: `swift build` — Expected: `Build complete!`
```bash
git add -A && git commit -m "feat: TranscriptParser (tested) + TranscriptIO glob/tail last-prompt"
```

---

### Task 8: AgentService — polling loop, groups, last prompts, badge (M1/M2)

**Files:**
- Create: `Sources/AgentMonitor/Services/AgentService.swift`

**Interfaces:**
- Consumes: `ClaudeCLI`, `TranscriptIO`, `groupSessions`, `SessionGroups`.
- Produces:
  - `@MainActor @Observable final class AgentService` with: `var groups = SessionGroups(yourTurn: [], working: [], recentlyDone: [], activeBadge: 0)`, `var lastPrompts: [String: String] = [:]`, `var lastActivity: [String: Date] = [:]`, `var errorMessage: String?`, `func start()`, `func stop()`, `func refreshNow() async`.

- [ ] **Step 1: Implement**

```swift
import Foundation
import Observation
import AgentMonitorCore

@MainActor
@Observable
final class AgentService {
    private(set) var groups = SessionGroups(yourTurn: [], working: [], recentlyDone: [], activeBadge: 0)
    private(set) var lastPrompts: [String: String] = [:]
    private(set) var lastActivity: [String: Date] = [:]
    var errorMessage: String?

    private let cli = ClaudeCLI()
    private var task: Task<Void, Never>?
    private var promptCache: [String: (size: UInt64, prompt: String?)] = [:]

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    func refreshNow() async {
        do {
            let sessions = try await cli.fetchSessions()
            errorMessage = nil
            // Off-main IO for mtimes + last prompts.
            let ids = sessions.map(\.sessionId)
            let io = await Task.detached { () -> (act: [String: Date], prompts: [String: String]) in
                var act: [String: Date] = [:]; var prompts: [String: String] = [:]
                for id in ids {
                    guard let path = TranscriptIO.transcriptPath(forSessionID: id) else { continue }
                    if let m = TranscriptIO.lastModified(path) { act[id] = m }
                    if let p = TranscriptIO.lastPrompt(forSessionID: id) { prompts[id] = p }
                }
                return (act, prompts)
            }.value
            self.lastActivity = io.act
            self.lastPrompts = io.prompts
            self.groups = groupSessions(sessions, lastActivity: io.act, now: Date())
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.groups = SessionGroups(yourTurn: [], working: [], recentlyDone: [], activeBadge: 0)
        }
    }
}
```

- [ ] **Step 2: Build** — `swift build` — `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(app): AgentService polling loop with groups, last prompts, activity"
```

---

### Task 9: Theme + popover views — SessionListView, SessionRowView (M1/M2)

Match the visual reference `scratchpad/proposal-a-triage.html`.

**Files:**
- Create: `Sources/AgentMonitor/Views/Theme.swift`
- Create: `Sources/AgentMonitor/Views/SessionRowView.swift`
- Create: `Sources/AgentMonitor/Views/SessionListView.swift`
- Modify: `Sources/AgentMonitor/AgentMonitorApp.swift` (wire AgentService + badge)

**Interfaces:**
- Consumes: `AgentService`, `SessionGroups`, `AgentSession`, `relativeTime`.
- Produces: `SessionListView(service:)`, `SessionRowView(session:lastPrompt:lastActivity:onOpen:)`, `Theme` colors.

- [ ] **Step 1: Implement `Theme.swift`**

```swift
import SwiftUI

enum Theme {
    static let yourTurn = Color(red: 0.96, green: 0.63, blue: 0.14) // #F5A623
    static let working  = Color(red: 0.19, green: 0.82, blue: 0.35) // #30D158
    static let running  = Color(red: 0.04, green: 0.52, blue: 1.0)  // #0A84FF
    static let done     = Color(red: 0.56, green: 0.56, blue: 0.58) // #8E8E93

    static func dot(for s: AgentSession) -> Color {
        switch bucket(for: s) {
        case .yourTurn: return yourTurn
        case .working: return s.kind == .background ? running : working
        case .recentlyDone: return done
        }
    }
}
```

- [ ] **Step 2: Implement `SessionRowView.swift`**

```swift
import SwiftUI
import AgentMonitorCore

struct SessionRowView: View {
    let session: AgentSession
    let lastPrompt: String?
    let lastActivity: Date?
    let onOpen: () -> Void

    @State private var hovering = false

    private var promptText: String {
        if session.kind == .background { return session.name ?? lastPrompt ?? "—" }
        return lastPrompt ?? "—"
    }
    private var branch: String? { nil } // branch chip wired in Task 11 (from transcript); omit for now

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(Theme.dot(for: session)).frame(width: 8, height: 8).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.folder).fontWeight(.semibold).lineLimit(1)
                        Text(session.parentPath).foregroundStyle(.tertiary).font(.caption2).lineLimit(1)
                        Spacer()
                        if let a = lastActivity {
                            Text(relativeTime(from: a, now: Date())).foregroundStyle(.secondary).font(.caption2)
                        }
                    }
                    Text(promptText).foregroundStyle(.secondary).font(.callout).lineLimit(1)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 12)
            .background(hovering ? Color.white.opacity(0.06) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
```

- [ ] **Step 3: Implement `SessionListView.swift`**

```swift
import SwiftUI
import AgentMonitorCore

struct SessionListView: View {
    @Bindable var service: AgentService
    let onOpen: (AgentSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = service.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary).padding(16)
            } else if service.groups.yourTurn.isEmpty && service.groups.working.isEmpty && service.groups.recentlyDone.isEmpty {
                Text("No sessions running.").foregroundStyle(.secondary).padding(16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        section("Your turn", service.groups.yourTurn, tint: Theme.yourTurn)
                        section("Working now", service.groups.working, tint: Theme.working)
                        section("Recently done", service.groups.recentlyDone, tint: Theme.done, dim: true)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 380)
        .frame(maxHeight: 520)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [AgentSession], tint: Color, dim: Bool = false) -> some View {
        if !items.isEmpty {
            HStack(spacing: 6) {
                Text(title.uppercased()).font(.caption2).fontWeight(.semibold).foregroundStyle(tint)
                Text("\(items.count)").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
            ForEach(items) { s in
                SessionRowView(session: s, lastPrompt: service.lastPrompts[s.sessionId],
                               lastActivity: service.lastActivity[s.sessionId]) { onOpen(s) }
                    .opacity(dim ? 0.55 : 1)
            }
        }
    }
}
```

- [ ] **Step 4: Wire into the app with the badge**

Replace `Sources/AgentMonitor/AgentMonitorApp.swift`:
```swift
import SwiftUI
import AgentMonitorCore

@main
struct AgentMonitorApp: App {
    @State private var service = AgentService()
    @Environment(\.openWindow) private var openWindow

    init() { NSApplication.shared.setActivationPolicy(.accessory) }

    var body: some Scene {
        MenuBarExtra {
            SessionListView(service: service) { session in
                openWindow(id: "transcript", value: session.sessionId)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .task { service.start() }
        } label: {
            let badge = service.groups.activeBadge
            Image(systemName: "dot.radiowaves.left.and.right")
            if badge > 0 { Text("\(badge)") }
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "transcript", for: String.self) { $sessionId in
            if let sessionId { TranscriptView(sessionId: sessionId) }
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 5: Build + live run (visual check vs mockup)**

Run: `swift build` — Expected: `Build complete!`
Run: `swift run AgentMonitor` — click the menu-bar item; confirm the three sections render with real sessions, status dots, last-prompt lines, the active badge, and that the folder/last-prompt are legible. Compare against `scratchpad/proposal-a-triage.html`. (Note: `TranscriptView` exists as a stub until Task 10 — it may show a placeholder.)

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(ui): Triage popover — three sections, rows, active badge"
```

---

### Task 10: TranscriptStore + TranscriptView detail window (M2)

**Files:**
- Create: `Sources/AgentMonitor/Services/TranscriptStore.swift`
- Create: `Sources/AgentMonitor/Views/TranscriptView.swift`

**Interfaces:**
- Consumes: `TranscriptIO.transcriptPath`, `TranscriptParser.parseLine`, `TranscriptRecord`.
- Produces:
  - `@MainActor @Observable final class TranscriptStore { init(sessionID:); var records: [TranscriptRecord]; var notFound: Bool; func load() }`
  - `TranscriptView(sessionId: String)`.

- [ ] **Step 1: Implement `TranscriptStore.swift`** (history read only; watching added in Task 11)

```swift
import Foundation
import Observation
import AgentMonitorCore

@MainActor
@Observable
final class TranscriptStore {
    let sessionID: String
    private(set) var records: [TranscriptRecord] = []
    private(set) var notFound = false
    private var path: String?

    init(sessionID: String) { self.sessionID = sessionID }

    func load() {
        guard let p = TranscriptIO.transcriptPath(forSessionID: sessionID) else { notFound = true; return }
        path = p
        let lines = (try? String(contentsOfFile: p, encoding: .utf8))?.components(separatedBy: "\n") ?? []
        records = lines.compactMap(TranscriptParser.parseLine)
            .filter { ($0.role == .user || $0.role == .assistant) && !$0.isMeta }
    }
}
```

- [ ] **Step 2: Implement `TranscriptView.swift`**

```swift
import SwiftUI
import AgentMonitorCore

struct TranscriptView: View {
    let sessionId: String
    @State private var store: TranscriptStore

    init(sessionId: String) {
        self.sessionId = sessionId
        _store = State(initialValue: TranscriptStore(sessionID: sessionId))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if store.notFound {
                    Text("No transcript found for this session yet.").foregroundStyle(.secondary)
                }
                ForEach(store.records) { rec in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rec.role == .user ? "You" : "Claude")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(rec.role == .user ? Theme.yourTurn : .secondary)
                        if !rec.text.isEmpty {
                            Text(rec.text).textSelection(.enabled)
                        }
                        ForEach(rec.toolUses, id: \.self) { tool in
                            Text("⌘ \(tool)").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 480)
        .navigationTitle("Session \(sessionId.prefix(8))")
        .onAppear { store.load() }
    }
}
```

- [ ] **Step 3: Build + live run**

Run: `swift build && swift run AgentMonitor` — click a row's Open; the detail window opens and renders that session's user/assistant turns. Verify `notFound` path by opening a session whose `.jsonl` doesn't exist yet (e.g. a just-started background job).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(m2): TranscriptStore history read + detail window"
```

---

### Task 11: Live follow — DispatchSource watch, incremental append, auto-scroll, pulse, branch chip (M3)

**Files:**
- Modify: `Sources/AgentMonitor/Services/TranscriptStore.swift` (add incremental watch)
- Modify: `Sources/AgentMonitor/Views/TranscriptView.swift` (auto-scroll)
- Modify: `Sources/AgentMonitor/Views/SessionRowView.swift` (working pulse + branch chip)
- Modify: `Sources/AgentMonitorCore/TranscriptParser.swift` (add `lastGitBranch(in:)`)
- Test: `Tests/AgentMonitorCoreTests/TranscriptParserTests.swift` (add a branch test)

**Interfaces:**
- Produces: `TranscriptParser.lastGitBranch(in lines: [String]) -> String?`; `TranscriptStore.startWatching()` / `stopWatching()`; AgentService exposes `gitBranches: [String: String]`.

- [ ] **Step 1: Add failing test for branch extraction**

Add to `TranscriptParserTests` (append a line with `"gitBranch":"main"` to the fixture first, or use an inline string):
```swift
func test_lastGitBranch() {
    let lines = [#"{"type":"assistant","gitBranch":"feature/audit-reports","message":{"role":"assistant","content":[]}}"#]
    XCTAssertEqual(TranscriptParser.lastGitBranch(in: lines), "feature/audit-reports")
}
func test_lastGitBranch_ignores_HEAD() {
    let lines = [#"{"type":"assistant","gitBranch":"HEAD","message":{"role":"assistant","content":[]}}"#]
    XCTAssertNil(TranscriptParser.lastGitBranch(in: lines)) // detached HEAD is not a useful chip
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter TranscriptParserTests` — FAIL.

- [ ] **Step 3: Implement `lastGitBranch`** in `TranscriptParser`:
```swift
public static func lastGitBranch(in lines: [String]) -> String? {
    for line in lines.reversed() {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let b = obj["gitBranch"] as? String, !b.isEmpty, b != "HEAD" else { continue }
        return b
    }
    return nil
}
```

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Wire branch into TranscriptIO + AgentService**

Add to `TranscriptIO`:
```swift
static func lastBranch(forSessionID id: String, maxBytes: Int = 64_000) -> String? {
    guard let path = transcriptPath(forSessionID: id),
          let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
    try? handle.seek(toOffset: start)
    guard let data = try? handle.readToEnd(), let str = String(data: data, encoding: .utf8) else { return nil }
    var lines = str.components(separatedBy: "\n"); if start > 0 { lines.removeFirst() }
    return TranscriptParser.lastGitBranch(in: lines)
}
```
In `AgentService` add `private(set) var gitBranches: [String: String] = [:]` and populate it inside the detached IO block alongside prompts; assign after. Pass `service.gitBranches[s.sessionId]` into `SessionRowView` as a `branch:` parameter and render it as a small chip beside the recency time. Replace the `private var branch: String? { nil }` stub with the passed value.

- [ ] **Step 6: Add the working pulse** in `SessionRowView` — when `bucket(for: session) == .working`, animate the dot's opacity:
```swift
// add: @State private var pulse = false
// dot:
Circle().fill(Theme.dot(for: session)).frame(width: 8, height: 8)
    .opacity(bucket(for: session) == .working ? (pulse ? 0.4 : 1) : 1)
    .padding(.top, 5)
    .onAppear {
        if bucket(for: session) == .working {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
```

- [ ] **Step 7: Add incremental watch to `TranscriptStore`**

```swift
import Dispatch
// add stored properties:
private var source: DispatchSourceFileSystemObject?
private var fileHandle: FileHandle?
private var offset: UInt64 = 0
private var partial = ""

func startWatching() {
    guard let p = path, let fh = FileHandle(forReadingAtPath: p) else { return }
    fileHandle = fh
    offset = (try? fh.seekToEnd()) ?? 0
    let src = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fh.fileDescriptor, eventMask: [.write, .extend], queue: .main)
    src.setEventHandler { [weak self] in self?.readAppended() }
    src.setCancelHandler { [weak self] in try? self?.fileHandle?.close() }
    source = src
    src.resume()
}

func stopWatching() { source?.cancel(); source = nil }

private func readAppended() {
    guard let fh = fileHandle else { return }
    try? fh.seek(toOffset: offset)
    guard let data = try? fh.readToEnd(), !data.isEmpty else { return }
    offset += UInt64(data.count)
    partial += String(data: data, encoding: .utf8) ?? ""
    // Only parse up to the last newline; keep the remainder buffered (DISCOVERY §2).
    guard let lastNL = partial.lastIndex(of: "\n") else { return }
    let complete = String(partial[..<lastNL])
    partial = String(partial[partial.index(after: lastNL)...])
    let new = complete.components(separatedBy: "\n").compactMap(TranscriptParser.parseLine)
        .filter { ($0.role == .user || $0.role == .assistant) && !$0.isMeta }
    records.append(contentsOf: new)
}
```
Call `startWatching()` after `load()` in `TranscriptView.onAppear`, and `stopWatching()` in `.onDisappear`.

- [ ] **Step 8: Auto-scroll** — wrap the `LazyVStack` in a `ScrollViewReader`, tag the last record, and `.onChange(of: store.records.count) { proxy.scrollTo(lastID, anchor: .bottom) }`.

- [ ] **Step 9: Build + live run**

Run: `swift build && swift run AgentMonitor`. Open a transcript for a **busy** session and confirm new turns append live and the view auto-scrolls. Confirm the working-section dots pulse and branch chips appear for non-HEAD sessions.

- [ ] **Step 10: Commit**

```bash
git add -A && git commit -m "feat(m3): live transcript follow, auto-scroll, working pulse, branch chip"
```

---

### Task 12: Polish — material, binary-not-found UX, empty states, launch-at-login (M4)

**Files:**
- Modify: `Sources/AgentMonitor/Views/SessionListView.swift` (popover material + refined empty/error)
- Modify: `Sources/AgentMonitor/Views/TranscriptView.swift` (header bar with branch/model/status + "Waiting for you" banner)
- Create: `Sources/AgentMonitor/Views/Theme.swift` material modifier

**Interfaces:**
- Consumes: existing views/services.
- Produces: a `.popoverMaterial()` ViewModifier; a header in TranscriptView.

- [ ] **Step 1: Add popover material** to `Theme.swift`:
```swift
import SwiftUI
extension View {
    func popoverMaterial() -> some View {
        self.background(.ultraThinMaterial).environment(\.colorScheme, .dark)
    }
}
```
Apply `.popoverMaterial()` to the root `VStack` in `SessionListView`.

- [ ] **Step 2: Refined error state** — when `service.errorMessage` reflects `binaryNotFound`, show the message plus the searched paths in a monospaced caption, with a hint to install Claude Code. (The message already contains the paths from `ClaudeCLIError.binaryNotFound`.)

- [ ] **Step 3: TranscriptView header** — a top bar showing `folder · branch · model · status`; if the session is in the `yourTurn` bucket, a slim amber "Waiting for you" banner under the header. (Pass the `AgentSession` into the window via the existing `service.groups` lookup by `sessionId`, or thread folder/branch through the window value.)

- [ ] **Step 4: Launch-at-login (optional, YAGNI gate)** — add a `SettingsLink`/menu toggle using `SMAppService.mainApp.register()` only if desired. If skipped, note it in README as a future nicety.

- [ ] **Step 5: Build + live visual pass** — `swift build && swift run AgentMonitor`; compare side-by-side with `scratchpad/proposal-a-triage.html`. Adjust spacing/weights to match.

- [ ] **Step 6: Update README** with build/run instructions and a screenshot. Commit:
```bash
git add -A && git commit -m "feat(m4): material, binary-not-found UX, transcript header, polish"
```

---

## Self-Review

**1. Spec coverage:**
- (a) directory → `AgentSession.folder`/`parentPath` (Task 2), rendered Task 9 ✓
- (b) last prompt → `TranscriptParser.lastUserPrompt` + `TranscriptIO.lastPrompt` (Task 7), shown Task 9 ✓
- (c) status → buckets + dots (Tasks 4, 9) ✓
- (d) waiting on you → "Your turn" section, top of popover (Tasks 4, 9) ✓
- geeky metadata → branch chip + pulse (Task 11), model/msgs via header/hover (Tasks 9, 12) ✓
- architecture (Core lib + executable, 4 services) → Tasks 1–11 ✓
- gotchas: PATH (Task 5/6), defensive parse (Tasks 2, 7), partial line (Task 11 buffer), poll+watch (Tasks 8, 11), privacy (read-only throughout) ✓
- build setup SwiftPM + .accessory + macOS 14 (Task 1) ✓
- testing TranscriptParser (Task 7) incl. malformed/partial/tool-result/unknown ✓
- milestones M0–M4 mapped to Tasks 1 / 2–9 / 7–10 / 11 / 12 ✓

**2. Placeholder scan:** No "TBD/handle edge cases" hand-waves; every code step has concrete code. The one deferred item (`branch` stub returning nil in Task 9) is explicitly replaced in Task 11 — flagged, not silent. Launch-at-login is an explicit YAGNI gate, not a placeholder.

**3. Type consistency:** `SessionGroups`, `bucket(for:)`, `groupSessions(_:lastActivity:now:)`, `TranscriptRecord` fields, `TranscriptParser.parseLine/lastUserPrompt/lastGitBranch`, `TranscriptIO.transcriptPath/lastModified/lastPrompt/lastBranch`, `AgentService.groups/lastPrompts/lastActivity/gitBranches`, and the `openWindow(id:"transcript", value: sessionId)` ↔ `WindowGroup(id:"transcript", for: String.self)` pairing are consistent across tasks.
