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
        if let message = obj["message"] as? [String: Any] {
            model = message["model"] as? String
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
                                isToolResult: isToolResult, isMeta: isMeta, timestamp: ts, model: model)
    }

    /// Whether the most recent assistant turn (with text) ends by asking a question.
    /// Used to tell "waiting for you" apart from merely "idle".
    public static func lastAssistantAsksQuestion(in lines: [String]) -> Bool {
        for line in lines.reversed() {
            guard let r = parseLine(line) else { continue }
            if r.role == .assistant {
                let t = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }   // skip tool-only assistant turns
                return t.hasSuffix("?")
            }
            if r.role == .user, !r.isMeta, !r.isToolResult { return false } // user already replied
        }
        return false
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
