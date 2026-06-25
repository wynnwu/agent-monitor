import Foundation
import AgentMonitorCore

enum TranscriptIO {
    static var projectsDir: String { "\(NSHomeDirectory())/.claude/projects" }

    /// Glob by sessionId — do NOT reconstruct the slug (DISCOVERY §2).
    static func transcriptPath(forSessionID id: String) -> String? {
        let matches = (try? FileManager.default.contentsOfDirectory(atPath: projectsDir)) ?? []
        for slug in matches {
            let candidate = "\(projectsDir)/\(slug)/\(id).jsonl"
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    static func lastModified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func fileSize(_ path: String) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Read the tail of the transcript and return the trailing lines (dropping a possibly
    /// truncated first line when we didn't start at byte 0). Cheap on huge transcripts.
    private static func tailLines(_ path: String, maxBytes: Int) -> [String]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let str = String(data: data, encoding: .utf8) else { return nil }
        var lines = str.components(separatedBy: "\n")
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    /// Branch + "asks a question" come from the recent tail (cheap). The last *user*
    /// prompt can be much further back (after a big final exchange), so if it isn't in
    /// the first tail we escalate the read until it's found.
    static func tailInfo(atPath path: String, maxBytes: Int = 64_000)
        -> (prompt: String?, branch: String?, asksQuestion: Bool) {
        guard let lines = tailLines(path, maxBytes: maxBytes) else { return (nil, nil, false) }
        let branch = TranscriptParser.lastGitBranch(in: lines)
        let asks = TranscriptParser.lastAssistantAsksQuestion(in: lines)
        var prompt = TranscriptParser.lastUserPrompt(in: lines)
        if prompt == nil {
            for cap in [512_000, Int.max] {
                guard let more = tailLines(path, maxBytes: cap) else { break }
                if let p = TranscriptParser.lastUserPrompt(in: more) { prompt = p; break }
                if cap == Int.max { break } // whole file already read; give up
            }
        }
        return (prompt, branch, asks)
    }
}
