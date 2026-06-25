import XCTest
@testable import AgentMonitorCore

final class PollingTests: XCTestCase {
    func i(_ current: Double, _ fast: Bool) -> Double {
        nextPollInterval(current: current, fast: fast, minInterval: 10, maxInterval: 30)
    }

    func test_fast_snaps_to_min() {
        XCTAssertEqual(i(10, true), 10)
        XCTAssertEqual(i(30, true), 10) // active again → back to fast immediately
    }

    func test_idle_backs_off_doubling() {
        XCTAssertEqual(i(10, false), 20)
    }

    func test_idle_caps_at_max() {
        XCTAssertEqual(i(20, false), 30) // 40 clamped
        XCTAssertEqual(i(30, false), 30)
    }
}
