import Foundation

/// Locations probed for the GitHub CLI (Apple silicon Homebrew, Intel Homebrew, system).
let ghPath: String? = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }

/// Runs a tool without blocking a Swift-concurrency thread; cancelling the task terminates the process.
func runAsync(_ exe: String, _ args: [String]) async -> (status: Int32, out: String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"; env["GH_PROMPT_DISABLED"] = "1"
    p.environment = env
    let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
    return await withTaskCancellationHandler {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                do { try p.run() } catch { cont.resume(returning: (-1, "")); return }
                let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus, String(decoding: d, as: UTF8.self)))
            }
        }
    } onCancel: { if p.isRunning { p.terminate() } }
}
