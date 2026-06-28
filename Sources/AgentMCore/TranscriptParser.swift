import Foundation

public enum TranscriptParser {
    // Read-only use (date(from:)) is thread-safe on modern Foundation.
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
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
        var model: String? = nil
        var stopReason: String? = nil
        if let message = obj["message"] as? [String: Any] {
            model = message["model"] as? String
            stopReason = message["stop_reason"] as? String
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
                                isToolResult: isToolResult, isMeta: isMeta, timestamp: ts,
                                model: model, stopReason: stopReason)
    }

    /// Whether the most recent assistant turn has handed the conversation back to you and is
    /// awaiting a reply — a literal question *or* a declarative "waiting on you" sign-off.
    /// Used to tell "waiting for you" apart from merely "idle", and (because it requires a
    /// *completed* `end_turn`) it's safe to trust even when the CLI still reports `busy`.
    public static func lastAssistantAsksQuestion(in lines: [String]) -> Bool {
        for line in lines.reversed() {
            guard let r = parseLine(line) else { continue }
            if r.role == .assistant {
                let t = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }   // skip tool-only assistant turns
                // A turn that stopped to run a tool (stop_reason "tool_use") is still working,
                // not awaiting you. Only a completed turn (end_turn, or older records with no
                // stop_reason) counts.
                if let sr = r.stopReason, sr != "end_turn" { return false }
                return solicitsUserInput(t)
            }
            if r.role == .user, !r.isMeta, !r.isToolResult { return false } // user already replied
        }
        return false
    }

    /// Does this closing assistant turn solicit a reply? A trailing `?`, or a declarative
    /// hand-off ("let me know", "I'll wait for your word", "want me to…"). Necessarily fuzzy;
    /// cues are matched against the message's closing to limit incidental mid-text matches.
    static func solicitsUserInput(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasSuffix("?") { return true }
        let tail = String(lower.suffix(200))
        let cues = [
            "let me know", "want me to", "should i ", "shall i ", "would you like",
            "do you want", "your call", "up to you", "say the word", "standing by",
            "ready when you", "your move", "wait for your", "waiting for your",
            "for your word", "for your go", "for your input", "for your call",
            "waiting on you", "which would you prefer", "your decision",
        ]
        return cues.contains { tail.contains($0) }
    }

    /// The last meaningful git branch recorded in the transcript. Ignores detached "HEAD".
    public static func lastGitBranch(in lines: [String]) -> String? {
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let b = obj["gitBranch"] as? String, !b.isEmpty, b != "HEAD" else { continue }
            return b
        }
        return nil
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
