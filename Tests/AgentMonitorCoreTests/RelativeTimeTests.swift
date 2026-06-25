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
