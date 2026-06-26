import SwiftUI
import AgentMonitorCore

/// Renders the popover to a PNG. Sample data below is entirely fictional — used for
/// README screenshots and design verification (no real local sessions).
@MainActor
enum SnapshotSupport {
    static func render(to path: String) {
        let view = SessionListView(
            groups: sampleGroups(),
            lastPrompts: samplePrompts,
            lastActivity: sampleActivity,
            gitBranches: sampleBranches,
            errorMessage: nil,
            onOpen: { _ in },
            scrollable: false
        )
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .environment(\.colorScheme, .dark)
        write(view, to: path)
    }

    // MARK: - Fictional sample data (no real local information)

    private static func s(_ id: String, _ cwd: String, _ kind: AgentSession.Kind,
                          status: AgentSession.Status? = nil, state: AgentSession.State? = nil,
                          name: String? = nil) -> AgentSession {
        AgentSession(sessionId: id, cwd: cwd, kind: kind, status: status, state: state, name: name)
    }

    static let sampleSessions: [AgentSession] = [
        s("acme-web", "/Users/dev/Code/acme/acme-web", .interactive, status: .idle),
        s("design-system", "/Users/dev/Code/acme/design-system", .interactive, status: .idle),
        s("blog-engine", "/Users/dev/Code/personal/blog-engine", .interactive, status: .idle),
        s("infra", "/Users/dev/Code/acme/infra", .background, status: .idle, state: .done,
          name: "provision-staging-cluster"),
        s("billing-service", "/Users/dev/Code/acme/billing-service", .interactive, status: .idle),
        s("mobile-app", "/Users/dev/Code/acme/mobile-app", .interactive, status: .idle),
        s("ml-pipeline", "/Users/dev/Code/acme/ml-pipeline", .interactive, status: .busy),
        s("data-warehouse", "/Users/dev/Code/acme/data-warehouse", .interactive, status: .busy),
        s("api-gateway", "/Users/dev/Code/acme/api-gateway", .background, status: .idle, state: .working,
          name: "Run the nightly integration suite"),
    ]

    static let samplePrompts: [String: String] = [
        "acme-web": "Refactor the checkout flow to use the new payment SDK.",
        "design-system": "Add dark-mode tokens to the Button and Card components.",
        "blog-engine": "Fix the RSS feed date formatting.",
        "billing-service": "Fix the invoice rounding bug in monthly statements.",
        "mobile-app": "Migrate the settings screen to the new navigation stack.",
        "ml-pipeline": "Train the ranking model on the latest dataset.",
        "data-warehouse": "Backfill the events table for Q3.",
    ]

    static let sampleActivity: [String: Date] = {
        let now = Date()
        return [
            "ml-pipeline": now.addingTimeInterval(-30),
            "data-warehouse": now.addingTimeInterval(-50),
            "api-gateway": now.addingTimeInterval(-20),
            "billing-service": now.addingTimeInterval(-12 * 60),
            "mobile-app": now.addingTimeInterval(-3600),
            "acme-web": now.addingTimeInterval(-3 * 3600),
            "design-system": now.addingTimeInterval(-5 * 3600),
            "blog-engine": now.addingTimeInterval(-2 * 86400),
            "infra": now.addingTimeInterval(-8 * 86400),
        ]
    }()

    static let sampleBranches: [String: String] = [
        "acme-web": "main",
        "design-system": "feat/dark-mode",
        "blog-engine": "main",
        "billing-service": "fix/invoice-rounding",
        "mobile-app": "main",
        "ml-pipeline": "exp/ranking-v2",
        "data-warehouse": "main",
        "api-gateway": "main",
    ]

    // billing-service and mobile-app ended on a question → "Waiting for you".
    static let sampleAsksQuestion: [String: Bool] = ["billing-service": true, "mobile-app": true]

    static func sampleGroups() -> SessionGroups {
        groupSessions(sampleSessions, lastActivity: sampleActivity, asksQuestion: sampleAsksQuestion, now: Date())
    }

    // MARK: - Transcript snapshot (fictional conversation)

    static let sampleRecords: [TranscriptRecord] = [
        .init(id: "1", role: .user, text: "Refactor the checkout flow to use the new payment SDK.",
              toolUses: [], isToolResult: false, isMeta: false, timestamp: nil),
        .init(id: "2", role: .assistant, text: "On it — replacing the legacy PaymentGateway with the new SDK and updating the call sites.",
              toolUses: ["Bash"], isToolResult: false, isMeta: false, timestamp: nil),
        .init(id: "3", role: .assistant, text: "Swapped the gateway, migrated 6 call sites, and the unit tests pass.",
              toolUses: [], isToolResult: false, isMeta: false, timestamp: nil),
        .init(id: "4", role: .user, text: "Make sure we handle the declined-card case gracefully.",
              toolUses: [], isToolResult: false, isMeta: false, timestamp: nil),
        .init(id: "5", role: .assistant, text: "Done — added a typed DeclinedCard error with a retry prompt. Want me to add a Sentry breadcrumb for it too?",
              toolUses: ["Edit"], isToolResult: false, isMeta: false, timestamp: nil, model: "claude-opus-4-8"),
    ]

    static func renderTranscript(to path: String) {
        let target = TranscriptTarget(
            sessionId: "a1b2c3d4e5f60718",
            folder: "acme-web",
            parent: "/Users/dev/Code/acme",
            branch: "main",
            kind: "interactive",
            pid: 48213,
            startedAt: Date().addingTimeInterval(-3 * 3600).timeIntervalSince1970 * 1000
        )
        let view = TranscriptWindowBody(target: target, records: sampleRecords, notFound: false, scrollable: false)
        write(view, to: path)
    }

    /// Render the REAL themed window for a live session (last `historyLimit` turns).
    static func renderWindow(sessionID: String, to path: String) {
        let store = TranscriptStore(sessionID: sessionID)
        store.load()
        let target = TranscriptTarget(sessionId: sessionID,
                                      folder: "live session",
                                      parent: "(real transcript — last turns only)",
                                      branch: nil)
        let view = TranscriptWindowBody(target: target,
                                        records: store.records,
                                        notFound: store.notFound,
                                        scrollable: false)
        write(view, to: path)
    }

    /// Render the popover with the REAL current sessions (one synchronous `claude agents` call).
    static func renderLive(to path: String) {
        let home = NSHomeDirectory()
        guard let bin = resolveClaudeBinary(candidates: defaultClaudeCandidates(home: home),
                                            exists: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["agents", "--json", "--all"]
        let out = Pipe(); proc.standardOutput = out; proc.standardError = Pipe()
        proc.environment = ["HOME": home]
        try? proc.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        let sessions = AgentSession.decodeArray(from: data)
        var acts: [String: Date] = [:], prompts: [String: String] = [:], asks: [String: Bool] = [:], branches: [String: String] = [:]
        for s in sessions {
            guard let tp = TranscriptIO.transcriptPath(forSessionID: s.sessionId) else { continue }
            if let m = TranscriptIO.lastModified(tp) { acts[s.sessionId] = m }
            let info = TranscriptIO.tailInfo(atPath: tp)
            if let pr = info.prompt { prompts[s.sessionId] = pr }
            if let b = info.branch { branches[s.sessionId] = b }
            asks[s.sessionId] = info.asksQuestion
        }
        let groups = groupSessions(sessions, lastActivity: acts, asksQuestion: asks, now: Date())
        let view = SessionListView(groups: groups, lastPrompts: prompts, lastActivity: acts,
                                   gitBranches: branches, errorMessage: nil, onOpen: { _ in }, scrollable: false)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .environment(\.colorScheme, .dark)
        write(view, to: path)
    }

    static func renderSettings(to path: String) {
        let prefs = HotKeyPreferences(defaults: UserDefaults(suiteName: "agent-monitor.snapshot") ?? .standard)
        prefs.enabled = true
        write(SettingsView(prefs: prefs), to: path)
    }

    /// Illustration of the centered, bar-attached dropdown (mock menu bar + sample data).
    static func renderDropdown(to path: String) {
        let dropdown = VStack(spacing: 0) {
            SessionListView(groups: sampleGroups(), lastPrompts: samplePrompts,
                            lastActivity: sampleActivity, gitBranches: sampleBranches,
                            errorMessage: nil, onOpen: { _ in }, scrollable: false)
            Divider().opacity(0.4)
            HStack(spacing: 14) {
                Image(systemName: "arrow.clockwise")
                Image(systemName: "gearshape")
                Spacer()
                Text("⌃⌘A · esc").foregroundStyle(.tertiary)
                Text("Quit")
            }
            .font(.system(size: 13)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 902)
        .environment(\.colorScheme, .dark)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 12).allowsHitTesting(false)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 14,
                                          bottomTrailingRadius: 14, topTrailingRadius: 0))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)

        let scene = VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer()
                Image(systemName: "dot.radiowaves.left.and.right")
                Text("4")
                Color.clear.frame(width: 10)
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.9))
            .frame(height: 26).frame(maxWidth: .infinity)
            .background(.black.opacity(0.85))

            dropdown
            Spacer(minLength: 40)
        }
        .frame(width: 1120, height: 600)
        .environment(\.colorScheme, .dark)
        .background(
            LinearGradient(colors: [Color(red: 0.20, green: 0.23, blue: 0.30), Color(red: 0.12, green: 0.12, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom)
        )
        write(scene, to: path)
    }

    /// Render a 1024×1024 app icon (squircle with margin + the radiowaves glyph).
    static func renderIcon(to path: String) {
        let size: CGFloat = 1024
        let icon = ZStack {
            RoundedRectangle(cornerRadius: size * 0.82 * 0.2237, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.22, green: 0.56, blue: 1.0),
                                              Color(red: 0.03, green: 0.13, blue: 0.42)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.82, height: size * 0.82)
                .shadow(color: .black.opacity(0.28), radius: size * 0.03, y: size * 0.015)
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)

        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private static func write<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
