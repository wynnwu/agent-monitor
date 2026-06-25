import SwiftUI
import AgentMonitorCore

struct SessionRowView: View {
    let session: AgentSession
    let lastPrompt: String?
    let lastActivity: Date?
    let branch: String?
    let bucket: StatusBucket
    let onOpen: () -> Void

    @State private var hovering = false
    @State private var pulse = false

    private var isWorking: Bool { bucket == .working }
    private var promptText: String {
        if session.kind == .background { return session.name ?? lastPrompt ?? "—" }
        return lastPrompt ?? "—"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Theme.dot(bucket: bucket, session: session))
                    .frame(width: 9, height: 9)
                    .opacity(isWorking && pulse ? 0.35 : 1)
                    .padding(.top, 5)
                    .onAppear {
                        guard isWorking else { return }
                        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.folder).font(.system(size: 16, weight: .semibold))
                            .lineLimit(1).layoutPriority(1)
                        Text(session.parentPath).font(.system(size: 12)).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        if let a = lastActivity {
                            Text(relativeTime(from: a, now: Date()))
                                .font(.system(size: 13)).foregroundStyle(.tertiary).monospacedDigit()
                        }
                    }
                    Text(promptText).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                    if let branch { branchChip(branch) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(hovering ? Color.white.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func branchChip(_ name: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
            Text(name).font(.system(size: 11)).lineLimit(1)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Color.white.opacity(0.07), in: Capsule())
    }
}
