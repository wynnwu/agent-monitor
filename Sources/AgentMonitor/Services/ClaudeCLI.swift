import Foundation
import AgentMonitorCore

enum ClaudeCLIError: Error, LocalizedError {
    case binaryNotFound([String])
    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let paths):
            return "Couldn't find the `claude` binary. Looked in:\n" + paths.joined(separator: "\n")
        }
    }
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
        let data = try await run(binary, ["agents", "--json", "--all"])
        return AgentSession.decodeArray(from: data)
    }

    private func run(_ launchPath: String, _ args: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            // Spawn off the main actor so the poll never stalls the UI.
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: launchPath)
                proc.arguments = args
                let out = Pipe(); proc.standardOutput = out
                proc.standardError = Pipe()
                // Minimal env; PATH is irrelevant since we use an absolute launch path.
                proc.environment = ["HOME": NSHomeDirectory()]
                do {
                    try proc.run()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    cont.resume(returning: data)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
