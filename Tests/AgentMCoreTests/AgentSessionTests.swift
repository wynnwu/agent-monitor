import XCTest
@testable import AgentMCore

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
