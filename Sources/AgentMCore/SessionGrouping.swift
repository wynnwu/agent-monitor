import Foundation

public enum StatusBucket: Sendable { case idle, waitingForYou, working }

/// Three-way classification:
/// - working: actively processing (interactive `busy`, or a running background job)
/// - waitingForYou: blocked on you — a permission/input prompt (`waiting`/`blocked`), or an
///   idle interactive session whose last assistant turn asked a question
/// - idle: everything else (quiet sessions, a session sitting at a `shell`, finished jobs)
///
/// Interactive status vocabulary: `busy`, `shell`, `idle`, `waiting`. `registryStatus`, when
/// supplied, is the per-PID registry status and takes precedence over the CLI's `status` —
/// it's fresher and finer-grained (the CLI collapses `shell`/`waiting` into `busy`).
public func bucket(for s: AgentSession, asksQuestion: Bool, registryStatus: String? = nil) -> StatusBucket {
    switch s.kind {
    case .interactive:
        switch registryStatus ?? s.status?.rawValue {
        case "busy":    return .working
        case "waiting": return .waitingForYou               // permission prompt / input request
        case "shell":   return .idle                        // a sub-state of idle (shell context)
        default:        return asksQuestion ? .waitingForYou : .idle   // "idle", nil, or unknown
        }
    case .background:
        switch s.state {
        case .working:                        return .working
        case .blocked:                        return .waitingForYou
        case .done, .failed, .stopped, .none: return .idle
        }
    }
}

public struct SessionGroups: Sendable {
    public let idle: [AgentSession]
    public let waitingForYou: [AgentSession]
    public let working: [AgentSession]
    public let activeBadge: Int
    public init(idle: [AgentSession], waitingForYou: [AgentSession], working: [AgentSession], activeBadge: Int) {
        self.idle = idle; self.waitingForYou = waitingForYou
        self.working = working; self.activeBadge = activeBadge
    }
}

/// Next poll interval: snap to `minInterval` when active/changing/watched, else
/// exponentially back off (×2) up to `maxInterval`.
public func nextPollInterval(current: Double, fast: Bool, minInterval: Double, maxInterval: Double) -> Double {
    fast ? minInterval : min(current * 2, maxInterval)
}

public func groupSessions(_ sessions: [AgentSession],
                          lastActivity: [String: Date],
                          asksQuestion: [String: Bool],
                          registryStatus: [String: String] = [:],
                          now: Date) -> SessionGroups {
    func activity(_ s: AgentSession) -> Date {
        lastActivity[s.sessionId] ?? s.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
    }
    var idle: [AgentSession] = [], waiting: [AgentSession] = [], working: [AgentSession] = []
    for s in sessions {
        switch bucket(for: s, asksQuestion: asksQuestion[s.sessionId] ?? false,
                      registryStatus: registryStatus[s.sessionId]) {
        case .idle: idle.append(s)
        case .waitingForYou: waiting.append(s)
        case .working: working.append(s)
        }
    }
    idle.sort { activity($0) > activity($1) }
    waiting.sort { activity($0) > activity($1) }
    working.sort { activity($0) > activity($1) }
    // The badge is exactly the working bucket, so it inherits the registry override.
    return SessionGroups(idle: idle, waitingForYou: waiting, working: working, activeBadge: working.count)
}
