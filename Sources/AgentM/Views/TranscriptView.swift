import SwiftUI
import AgentMCore

/// What a transcript window needs to know, captured when it's opened.
struct TranscriptTarget: Codable, Hashable {
    let sessionId: String
    let folder: String
    let parent: String
    let branch: String?
    var kind: String = "interactive"
    var pid: Int? = nil
    var startedAt: Double? = nil   // epoch milliseconds
}

enum TranscriptFilter: String, CaseIterable, Identifiable {
    case all, prompts, responses
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .prompts: return "Prompts"
        case .responses: return "Responses"
        }
    }
    func includes(_ role: TranscriptRecord.Role) -> Bool {
        switch self {
        case .all: return true
        case .prompts: return role == .user
        case .responses: return role == .assistant
        }
    }
}

struct TranscriptView: View {
    let target: TranscriptTarget
    @State private var store: TranscriptStore

    init(target: TranscriptTarget) {
        self.target = target
        _store = State(initialValue: TranscriptStore(sessionID: target.sessionId))
    }

    var body: some View {
        TranscriptWindowBody(target: target, records: store.records, notFound: store.notFound)
            .onAppear { store.load(); store.startWatching() }
            .onDisappear { store.stopWatching() }
    }
}

/// The themed window chrome (geeky header, filter, waiting banner, turns).
/// Reusable so it can be rendered for verification with `scrollable: false`.
struct TranscriptWindowBody: View {
    let target: TranscriptTarget
    let records: [TranscriptRecord]
    var notFound: Bool = false
    var scrollable: Bool = true

    @State private var filter: TranscriptFilter = .all

    private var waitingForYou: Bool { records.last?.role == .assistant }
    private var visibleRecords: [TranscriptRecord] { records.filter { filter.includes($0.role) } }

    private var metaLine: String {
        var parts: [String] = []
        if let m = records.last(where: { $0.role == .assistant })?.model { parts.append(prettyModel(m)) }
        if let b = target.branch { parts.append(b) }
        parts.append(target.kind)
        if let pid = target.pid { parts.append("pid \(pid)") }
        if let s = target.startedAt { parts.append("up " + relativeTime(from: Date(timeIntervalSince1970: s / 1000), now: Date())) }
        parts.append("id \(target.sessionId.prefix(8))")
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.folder).font(.system(size: 18, weight: .semibold))
                    Text(target.parent).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    Text(metaLine).font(.system(size: 12)).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.tail).textSelection(.enabled)
                }
                HStack(spacing: 0) {
                    ForEach(TranscriptFilter.allCases) { f in
                        Button { filter = f } label: {
                            Text(f.label)
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .foregroundStyle(filter == f ? Color.primary : Color.secondary)
                                .background(filter == f ? Color.white.opacity(0.14) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)

            if waitingForYou && !notFound {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.left")
                    Text("Waiting for your reply")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.yourTurn)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Theme.yourTurn.opacity(0.12))
            }
            Divider().opacity(0.5)

            if notFound {
                ContentUnavailableView("No transcript yet",
                                       systemImage: "doc.text.magnifyingglass",
                                       description: Text("This session hasn't written a transcript file yet."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleRecords.isEmpty {
                ContentUnavailableView("Nothing to show",
                                       systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("No \(filter.label.lowercased()) in the last turns."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TranscriptContent(records: visibleRecords, scrollable: scrollable)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 580)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .environment(\.colorScheme, .dark)
        .navigationTitle(target.folder)
    }
}

struct TranscriptContent: View {
    let records: [TranscriptRecord]
    var scrollable: Bool = true

    var body: some View {
        if scrollable {
            ScrollView { turns.padding(14) }
                .defaultScrollAnchor(.bottom)   // open showing the latest turn at the bottom
        } else {
            turns.padding(14)
        }
    }

    @ViewBuilder
    private var turns: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(records) { rec in
                let isUser = rec.role == .user
                VStack(alignment: .leading, spacing: 4) {
                    Text(isUser ? "You" : "Claude")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isUser ? Theme.yourTurn : Color.secondary)
                    if !rec.text.isEmpty {
                        Text(rec.text).font(.system(size: 15)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(rec.toolUses, id: \.self) { tool in
                        Label(tool, systemImage: "wrench.and.screwdriver")
                            .font(.system(size: 13)).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(isUser ? Theme.yourTurn.opacity(0.10) : Color.white.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

/// "claude-opus-4-8" → "Opus 4.8". Falls back to the raw id for anything unusual.
func prettyModel(_ raw: String) -> String {
    var s = raw
    if s.hasPrefix("claude-") { s = String(s.dropFirst("claude-".count)) }
    let parts = s.split(separator: "-")
    guard let family = parts.first, family.first?.isLetter == true else { return raw }
    let version = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
    let fam = family.prefix(1).uppercased() + family.dropFirst()
    return version.isEmpty ? fam : "\(fam) \(version)"
}
