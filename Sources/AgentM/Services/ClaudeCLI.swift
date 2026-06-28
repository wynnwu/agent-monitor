import Foundation
import AgentMCore

enum ClaudeCLIError: Error, LocalizedError {
    case binaryNotFound([String])
    case timedOut(seconds: Int)
    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let paths):
            return "Couldn't find the `claude` binary. Looked in:\n" + paths.joined(separator: "\n")
        case .timedOut(let s):
            return "`claude agents` didn't respond within \(s)s."
        }
    }
}

/// Holds a `Process` so it can be safely referenced from the timeout timer's `@Sendable`
/// handler. We only touch `isRunning`/`terminate()` (thread-safe) and a locked flag.
private final class ProcBox: @unchecked Sendable {
    let proc: Process
    private let lock = NSLock()
    private var _timedOut = false
    init(_ proc: Process) { self.proc = proc }
    func markTimedOut() { lock.lock(); _timedOut = true; lock.unlock() }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return _timedOut }
}

struct ClaudeCLI: Sendable {
    func resolveBinary() throws -> String {
        let candidates = defaultClaudeCandidates(home: NSHomeDirectory())
        let fm = FileManager.default
        guard let path = resolveClaudeBinary(candidates: candidates, exists: { fm.isExecutableFile(atPath: $0) })
        else { throw ClaudeCLIError.binaryNotFound(candidates) }
        return path
    }

    func fetchSessions() async throws -> [AgentSession] {
        let binary = try resolveBinary()
        let data = try await run(binary, ["agents", "--json", "--all"], timeout: 15)
        return AgentSession.decodeArray(from: data)
    }

    private func run(_ launchPath: String, _ args: [String], timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            // Spawn off the main actor so the poll never stalls the UI.
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: launchPath)
                proc.arguments = args
                let out = Pipe(); proc.standardOutput = out
                proc.standardError = Pipe()
                // Minimal env; PATH is irrelevant since we use an absolute launch path.
                proc.environment = ["HOME": NSHomeDirectory()]

                // Watchdog: if `claude` hangs, terminate it so the poll loop can't wedge
                // forever on the blocking read below (terminating closes stdout → read returns).
                let box = ProcBox(proc)
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    if box.proc.isRunning { box.markTimedOut(); box.proc.terminate() }
                }
                timer.resume()

                do {
                    try proc.run()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    timer.cancel()
                    if box.timedOut {
                        cont.resume(throwing: ClaudeCLIError.timedOut(seconds: Int(timeout)))
                    } else {
                        cont.resume(returning: data)
                    }
                } catch {
                    timer.cancel()
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
