import SwiftUI

@main
struct AgentMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Headless design-verification / debug paths: render and exit before any UI.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            SnapshotSupport.render(to: args[i + 1]); exit(0)
        }
        if let i = args.firstIndex(of: "--snapshot-transcript"), i + 1 < args.count {
            SnapshotSupport.renderTranscript(to: args[i + 1]); exit(0)
        }
        if let i = args.firstIndex(of: "--snapshot-window"), i + 2 < args.count {
            SnapshotSupport.renderWindow(sessionID: args[i + 1], to: args[i + 2]); exit(0)
        }
        if let i = args.firstIndex(of: "--snapshot-settings"), i + 1 < args.count {
            SnapshotSupport.renderSettings(to: args[i + 1]); exit(0)
        }
        if let i = args.firstIndex(of: "--snapshot-live"), i + 1 < args.count {
            SnapshotSupport.renderLive(to: args[i + 1]); exit(0)
        }
        if let i = args.firstIndex(of: "--snapshot-dropdown"), i + 1 < args.count {
            SnapshotSupport.renderDropdown(to: args[i + 1]); exit(0)
        }
        if let i = args.firstIndex(of: "--make-icon"), i + 1 < args.count {
            SnapshotSupport.renderIcon(to: args[i + 1]); exit(0)
        }
        if let i = args.firstIndex(of: "--count-transcript"), i + 1 < args.count {
            let store = TranscriptStore(sessionID: args[i + 1])
            store.load()
            FileHandle.standardError.write(Data("records=\(store.records.count) notFound=\(store.notFound)\n".utf8))
            exit(0)
        }
    }

    var body: some Scene {
        // Menu-bar app: the status item + popover + windows are managed by AppDelegate.
        // This no-op scene just satisfies the App's Scene requirement.
        Settings { EmptyView() }
    }
}
