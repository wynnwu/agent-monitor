import XCTest
@testable import AgentMCore

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

    func test_lastGitBranch() {
        let lines = [#"{"type":"assistant","gitBranch":"feature/audit-reports","message":{"role":"assistant","content":[]}}"#]
        XCTAssertEqual(TranscriptParser.lastGitBranch(in: lines), "feature/audit-reports")
    }

    func test_lastGitBranch_ignores_HEAD() {
        let lines = [#"{"type":"assistant","gitBranch":"HEAD","message":{"role":"assistant","content":[]}}"#]
        XCTAssertNil(TranscriptParser.lastGitBranch(in: lines)) // detached HEAD is not a useful chip
    }

    func test_lastAssistantAsksQuestion_true() {
        let lines = [#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Should I open a PR?"}]}}"#]
        XCTAssertTrue(TranscriptParser.lastAssistantAsksQuestion(in: lines))
    }

    func test_lastAssistantAsksQuestion_false() {
        let lines = [#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done."}]}}"#]
        XCTAssertFalse(TranscriptParser.lastAssistantAsksQuestion(in: lines))
    }

    func test_lastAssistantAsksQuestion_skips_trailing_tool_turn() {
        // A later tool-only assistant turn (no text) shouldn't mask the real question.
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Want me to proceed?"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]}}"#,
        ]
        XCTAssertTrue(TranscriptParser.lastAssistantAsksQuestion(in: lines))
    }
}
