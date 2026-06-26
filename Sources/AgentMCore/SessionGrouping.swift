import Foundation

public enum StatusBucket: Sendable { case idle, waitingForYou, working }

/// Three-way classification:
/// - working: actively processing (interactive busy, or a running background job)
/// - waitingForYou: idle interactive session whose last assistant turn asked a question
/// - idle: everything else not working (quiet interactive sessions, finished background jobs)
public func bucket(for s: AgentSession, asksQuestion: Bool) -> StatusBucket {
    switch s.kind {
    case .interactive:
        if s.status == .busy { return .working }
        return asksQuestion ? .waitingForYou : .idle
    case .background:
        return s.state == .working ? .working : .idle
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
                          now: Date) -> SessionGroups {
    func activity(_ s: AgentSession) -> Date {
        lastActivity[s.sessionId] ?? s.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
    }
    var idle: [AgentSession] = [], waiting: [AgentSession] = [], working: [AgentSession] = []
    for s in sessions {
        switch bucket(for: s, asksQuestion: asksQuestion[s.sessionId] ?? false) {
        case .idle: idle.append(s)
        case .waitingForYou: waiting.append(s)
        case .working: working.append(s)
        }
    }
    idle.sort { activity($0) > activity($1) }
    waiting.sort { activity($0) > activity($1) }
    working.sort { activity($0) > activity($1) }
    let badge = sessions.filter {
        ($0.kind == .interactive && $0.status == .busy) || ($0.kind == .background && $0.state == .working)
    }.count
    return SessionGroups(idle: idle, waitingForYou: waiting, working: working, activeBadge: badge)
}
