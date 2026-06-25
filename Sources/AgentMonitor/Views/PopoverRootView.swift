import SwiftUI
import AgentMonitorCore

/// The dropdown's content: the live session list plus a footer.
/// Reads `service` and `prefs` (@Observable) so it updates as they change.
struct PopoverRootView: View {
    let service: AgentService
    let prefs: HotKeyPreferences
    let onOpen: (AgentSession) -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    private let width: CGFloat = 300 * 3 + 2

    var body: some View {
        VStack(spacing: 0) {
            SessionListView(
                groups: service.groups,
                lastPrompts: service.lastPrompts,
                lastActivity: service.lastActivity,
                gitBranches: service.gitBranches,
                errorMessage: service.errorMessage,
                onOpen: onOpen
            )
            Divider().opacity(0.4)
            HStack(spacing: 14) {
                Button { Task { await service.refreshNow() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                Button { onSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Spacer()
                if prefs.enabled {
                    Text("\(prefs.display) · esc").foregroundStyle(.tertiary)
                }
                Button("Quit") { onQuit() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: width)
        .environment(\.colorScheme, .dark)
        // Translucent: a touch of alpha for legibility; the NSVisualEffectView behind
        // provides the glass blur, and rounds the bottom corners.
        .background(Color.black.opacity(0.12))
        // Soft shadow along the top edge sells "emerging from behind the menu bar".
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 12)
                .allowsHitTesting(false)
        }
    }
}
