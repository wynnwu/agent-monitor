import Foundation
import AgentMCore

/// Reads Claude Code's per-PID session registry (`~/.claude/sessions/<pid>.json`), which
/// carries a finer status than `claude agents --json` (e.g. `shell` vs the CLI's `busy`).
/// Read-only; never written.
enum SessionRegistryIO {
    static var sessionsDir: String { "\(NSHomeDirectory())/.claude/sessions" }

    /// Finer status for a live interactive session, or nil if the file is absent, malformed,
    /// or belongs to a different session (PID reuse).
    static func status(forPID pid: Int, expectedSessionID id: String) -> String? {
        let path = "\(sessionsDir)/\(pid).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return registryStatus(fromJSON: data, expectedSessionID: id)
    }
}
