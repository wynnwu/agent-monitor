import Foundation
import Dispatch
import Observation
import AgentMCore

@MainActor
@Observable
final class TranscriptStore {
    let sessionID: String
    private(set) var records: [TranscriptRecord] = []
    private(set) var notFound = false
    private(set) var path: String?

    /// Quick peek: how many recent turns to show on open, and how much of the
    /// file's tail to read to find them (avoids parsing huge histories).
    private let historyLimit: Int
    private let tailBytes: Int

    private var source: DispatchSourceFileSystemObject?
    private var fileHandle: FileHandle?
    private var offset: UInt64 = 0
    private var partial = ""   // buffered trailing bytes not yet terminated by a newline

    init(sessionID: String, historyLimit: Int = 12, tailBytes: Int = 256_000) {
        self.sessionID = sessionID
        self.historyLimit = historyLimit
        self.tailBytes = tailBytes
    }

    /// Load only the last `historyLimit` renderable turns by reading the tail of the file.
    func load() {
        guard let p = TranscriptIO.transcriptPath(forSessionID: sessionID) else { notFound = true; return }
        path = p
        guard let handle = FileHandle(forReadingAtPath: p) else { records = []; return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        offset = size                                   // watcher resumes from current EOF
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var lines = (String(data: data, encoding: .utf8) ?? "").components(separatedBy: "\n")
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // drop the partial head line
        partial = lines.last ?? ""                              // possibly-incomplete trailing line
        let all = Self.renderable(Array(lines.dropLast()))
        records = Array(all.suffix(historyLimit))
    }

    func startWatching() {
        guard let p = path, fileHandle == nil, let fh = FileHandle(forReadingAtPath: p) else { return }
        fileHandle = fh
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fh.fileDescriptor, eventMask: [.write, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readAppended() }
        }
        src.setCancelHandler { [weak self] in
            MainActor.assumeIsolated { try? self?.fileHandle?.close(); self?.fileHandle = nil }
        }
        source = src
        src.resume()
    }

    func stopWatching() { source?.cancel(); source = nil }

    private func readAppended() {
        guard let fh = fileHandle else { return }
        try? fh.seek(toOffset: offset)
        guard let data = try? fh.readToEnd(), !data.isEmpty else { return }
        offset += UInt64(data.count)
        partial += String(data: data, encoding: .utf8) ?? ""
        // Only parse through the last newline; keep the remainder buffered (DISCOVERY §2).
        guard let lastNL = partial.lastIndex(of: "\n") else { return }
        let complete = String(partial[..<lastNL])
        partial = String(partial[partial.index(after: lastNL)...])
        let new = Self.renderable(complete.components(separatedBy: "\n"))
        if !new.isEmpty { records.append(contentsOf: new) }
    }

    /// User/assistant turns worth showing: drop meta, and drop empty tool-result/echo turns.
    static func renderable(_ lines: [String]) -> [TranscriptRecord] {
        lines.compactMap(TranscriptParser.parseLine)
            .filter { ($0.role == .user || $0.role == .assistant) && !$0.isMeta }
            .filter { !$0.text.isEmpty || !$0.toolUses.isEmpty }
    }
}
