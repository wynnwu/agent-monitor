import XCTest
@testable import AgentMCore

final class SessionRegistryTests: XCTestCase {
    private func json(_ s: String) -> Data { Data(s.utf8) }

    func test_returns_status_when_sessionId_matches() {
        let d = json(#"{"pid":14455,"sessionId":"abc","status":"shell"}"#)
        XCTAssertEqual(registryStatus(fromJSON: d, expectedSessionID: "abc"), "shell")
    }

    // PID reuse guard: a registry file whose recorded sessionId doesn't match the session
    // we're asking about must be ignored (the PID was recycled by a different session).
    func test_nil_when_sessionId_mismatches() {
        let d = json(#"{"pid":14455,"sessionId":"other","status":"busy"}"#)
        XCTAssertNil(registryStatus(fromJSON: d, expectedSessionID: "abc"))
    }

    func test_nil_on_garbage_or_missing_fields() {
        XCTAssertNil(registryStatus(fromJSON: json("not json at all"), expectedSessionID: "abc"))
        XCTAssertNil(registryStatus(fromJSON: json(#"{"sessionId":"abc"}"#), expectedSessionID: "abc"))
        XCTAssertNil(registryStatus(fromJSON: json(#"{"sessionId":"abc","status":""}"#), expectedSessionID: "abc"))
    }
}
