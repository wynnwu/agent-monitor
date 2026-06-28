import XCTest
@testable import AgentMCore

final class SessionGroupingTests: XCTestCase {
    func mk(_ id: String, _ kind: AgentSession.Kind, status: AgentSession.Status? = nil,
            state: AgentSession.State? = nil) -> AgentSession {
        AgentSession(sessionId: id, cwd: "/p/\(id)", kind: kind, status: status, state: state)
    }

    func test_buckets() {
        XCTAssertEqual(bucket(for: mk("a", .interactive, status: .idle), asksQuestion: true), .waitingForYou)
        XCTAssertEqual(bucket(for: mk("a", .interactive, status: .idle), asksQuestion: false), .idle)
        // busy overrides any pending question
        XCTAssertEqual(bucket(for: mk("b", .interactive, status: .busy), asksQuestion: true), .working)
        XCTAssertEqual(bucket(for: mk("c", .background, state: .working), asksQuestion: false), .working)
        XCTAssertEqual(bucket(for: mk("d", .background, state: .done), asksQuestion: true), .idle)
    }

    func test_groups_and_badge() {
        let sessions = [
            mk("idle1", .interactive, status: .idle),
            mk("wait1", .interactive, status: .idle),
            mk("busy1", .interactive, status: .busy),
            mk("bgwork", .background, state: .working),
            mk("bgdone", .background, state: .done),
        ]
        let g = groupSessions(sessions, lastActivity: [:], asksQuestion: ["wait1": true], now: Date())
        XCTAssertEqual(Set(g.idle.map(\.sessionId)), ["idle1", "bgdone"])
        XCTAssertEqual(g.waitingForYou.map(\.sessionId), ["wait1"])
        XCTAssertEqual(Set(g.working.map(\.sessionId)), ["busy1", "bgwork"])
        XCTAssertEqual(g.activeBadge, 2) // busy1 + bgwork
    }

    // Regression: cvl-pinako showed as Working because `claude agents --json` reports an
    // interactive session in the "shell" state as `busy`. The per-PID registry knows the
    // finer truth ("shell"), and when present it must win over the CLI's collapsed value.
    func test_registryStatus_overrides_cli_busy() {
        // CLI says busy, registry says "shell" → NOT working.
        XCTAssertEqual(bucket(for: mk("p", .interactive, status: .busy), asksQuestion: false,
                              registryStatus: "shell"), .idle)
        // registry "busy" → working.
        XCTAssertEqual(bucket(for: mk("p", .interactive, status: .busy), asksQuestion: false,
                              registryStatus: "busy"), .working)
        // registry "idle" with a pending question → waiting (not working).
        XCTAssertEqual(bucket(for: mk("p", .interactive, status: .busy), asksQuestion: true,
                              registryStatus: "idle"), .waitingForYou)
        // no registry entry → fall back to the CLI status.
        XCTAssertEqual(bucket(for: mk("p", .interactive, status: .busy), asksQuestion: false,
                              registryStatus: nil), .working)
    }

    func test_registry_waiting_is_waitingForYou() {
        // `waiting` = blocked on a permission prompt / input request → needs you, even though
        // the CLI may report the same session as busy.
        XCTAssertEqual(bucket(for: mk("w", .interactive, status: .busy), asksQuestion: false,
                              registryStatus: "waiting"), .waitingForYou)
    }

    func test_cli_status_fallback_covers_full_vocabulary() {
        // No registry entry → fall back to the CLI status, which now models the full enum.
        XCTAssertEqual(bucket(for: mk("a", .interactive, status: .busy), asksQuestion: false), .working)
        XCTAssertEqual(bucket(for: mk("b", .interactive, status: .shell), asksQuestion: false), .idle)
        XCTAssertEqual(bucket(for: mk("c", .interactive, status: .waiting), asksQuestion: false), .waitingForYou)
        XCTAssertEqual(bucket(for: mk("d", .interactive, status: .idle), asksQuestion: true), .waitingForYou)
    }

    func test_background_states_map_correctly() {
        XCTAssertEqual(bucket(for: mk("w", .background, state: .working), asksQuestion: false), .working)
        XCTAssertEqual(bucket(for: mk("b", .background, state: .blocked), asksQuestion: false), .waitingForYou)
        XCTAssertEqual(bucket(for: mk("d", .background, state: .done), asksQuestion: false), .idle)
        XCTAssertEqual(bucket(for: mk("f", .background, state: .failed), asksQuestion: false), .idle)
        XCTAssertEqual(bucket(for: mk("s", .background, state: .stopped), asksQuestion: false), .idle)
        XCTAssertEqual(bucket(for: mk("n", .background, state: nil), asksQuestion: false), .idle)
    }

    func test_groups_registry_excludes_shell_from_working_and_badge() {
        let sessions = [
            mk("shellish", .interactive, status: .busy),   // cvl-pinako case
            mk("reallyBusy", .interactive, status: .busy),
        ]
        let g = groupSessions(sessions, lastActivity: [:], asksQuestion: [:],
                              registryStatus: ["shellish": "shell", "reallyBusy": "busy"],
                              now: Date())
        XCTAssertEqual(g.working.map(\.sessionId), ["reallyBusy"])
        XCTAssertEqual(g.idle.map(\.sessionId), ["shellish"])
        XCTAssertEqual(g.activeBadge, 1)
    }

    func test_sorted_recent_first() {
        let now = Date(timeIntervalSince1970: 1000)
        let old = mk("old", .interactive, status: .idle)
        let new = mk("new", .interactive, status: .idle)
        let g = groupSessions([old, new], lastActivity: [
            "old": now.addingTimeInterval(-1000),
            "new": now.addingTimeInterval(-10),
        ], asksQuestion: [:], now: now)
        XCTAssertEqual(g.idle.map(\.sessionId), ["new", "old"])
    }
}
