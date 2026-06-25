import XCTest
@testable import AgentMonitorCore

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
