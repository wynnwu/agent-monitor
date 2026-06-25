import SwiftUI
import AgentMonitorCore

enum Theme {
    static let waitingForYou = Color(red: 0.96, green: 0.63, blue: 0.14) // #F5A623 (amber)
    static let working = Color(red: 0.19, green: 0.82, blue: 0.35)        // #30D158 (green)
    static let running = Color(red: 0.04, green: 0.52, blue: 1.0)         // #0A84FF (blue)
    static let idle = Color(red: 0.56, green: 0.56, blue: 0.58)           // #8E8E93 (gray)

    /// Backwards-friendly alias used by the transcript view's "you" accent.
    static var yourTurn: Color { waitingForYou }

    /// Dot color for a row given the column it lives in.
    static func dot(bucket: StatusBucket, session: AgentSession) -> Color {
        switch bucket {
        case .waitingForYou: return waitingForYou
        case .idle: return idle
        case .working: return session.kind == .background ? running : working
        }
    }

    /// Column accent.
    static func tint(_ bucket: StatusBucket) -> Color {
        switch bucket {
        case .idle: return idle
        case .waitingForYou: return waitingForYou
        case .working: return working
        }
    }
}
