import XCTest
@testable import AgentMCore

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
