import Foundation

public struct AgentSession: Identifiable, Codable, Hashable, Sendable {
    public var id: String { sessionId }
    public let sessionId: String
    public let cwd: String
    public let kind: Kind
    public let status: Status?
    public let state: State?
    public let name: String?
    public let pid: Int?
    public let startedAt: Double?

    public enum Kind: String, Codable, Sendable { case interactive, background }
    // Per-turn activity for interactive sessions. Full vocabulary (from the CLI binary's
    // own validation set): the agent is `busy` processing, sitting at/after a `shell`
    // command (a sub-state of idle), plain `idle`, or `waiting` on you (permission prompt).
    public enum Status: String, Codable, Sendable { case idle, busy, shell, waiting }
    // Background-job lifecycle. `working` (incl. transient startup states), `blocked`
    // (waiting on your input/permission), or terminal `done`/`failed`/`stopped`.
    public enum State: String, Codable, Sendable { case working, blocked, done, failed, stopped }

    public var folder: String { URL(fileURLWithPath: cwd).lastPathComponent }

    public var parentPath: String {
        let parent = URL(fileURLWithPath: cwd).deletingLastPathComponent().path
        let home = NSHomeDirectory()
        if parent == home { return "~" }
        if parent.hasPrefix(home + "/") { return "~" + parent.dropFirst(home.count) }
        return parent
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, cwd, kind, status, state, name, pid, startedAt
    }

    public init(sessionId: String, cwd: String, kind: Kind, status: Status? = nil,
                state: State? = nil, name: String? = nil, pid: Int? = nil, startedAt: Double? = nil) {
        self.sessionId = sessionId; self.cwd = cwd; self.kind = kind
        self.status = status; self.state = state; self.name = name
        self.pid = pid; self.startedAt = startedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        cwd       = try c.decode(String.self, forKey: .cwd)
        kind      = try c.decode(Kind.self, forKey: .kind)         // unknown kind → throws → dropped
        status    = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? nil
        state     = (try? c.decodeIfPresent(State.self, forKey: .state)) ?? nil
        name      = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        pid       = (try? c.decodeIfPresent(Int.self, forKey: .pid)) ?? nil
        startedAt = (try? c.decodeIfPresent(Double.self, forKey: .startedAt)) ?? nil
    }

    /// Decode a JSON array, dropping any entry that fails (missing/invalid required field).
    /// Never throws — returns whatever decoded cleanly.
    public static func decodeArray(from data: Data) -> [AgentSession] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        let decoder = JSONDecoder()
        return raw.compactMap { element in
            guard let objData = try? JSONSerialization.data(withJSONObject: element) else { return nil }
            return try? decoder.decode(AgentSession.self, from: objData)
        }
    }
}
