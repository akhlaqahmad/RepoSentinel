import Foundation

enum Source: String, CaseIterable, Codable, Identifiable {
    case mac = "This Mac", local = "Local repos", remote = "GitHub"
    var id: String { rawValue }
    var icon: String { switch self { case .mac: "desktopcomputer"; case .local: "folder"; case .remote: "cloud" } }
}

enum Level: String, Codable { case malicious, review, benign }

struct Verdict: Codable, Hashable {
    var level: Level
    var reason: String
    var action: String
    var byAI: Bool
}

struct Finding: Identifiable, Hashable, Codable {
    var id = UUID()
    let source: Source
    let target: String          // repo path, owner/repo, or persistence item
    let file: String
    let excerpt: String
    let rule: String
    var branches: [String] = [] // remote only: every branch carrying the same hit
    var verdict: Verdict? = nil
    var isNew = false

    /// Stable identity across scans (used for ignore list and "new since last scan").
    var key: String { [source.rawValue, target, file, rule].joined(separator: "|") }
    var level: Level { verdict?.level ?? .malicious }   // unjudged = suspicious (fail loud)

    var url: URL? {
        guard source == .remote, let b = branches.first else { return nil }
        var c = URLComponents(); c.scheme = "https"; c.host = "github.com"
        c.path = "/\(target)/blob/\(b)/\(file)"
        return c.url
    }
    var localURL: URL? {
        switch source {
        case .local: return URL(fileURLWithPath: target).appendingPathComponent(file)
        case .mac: return target.hasPrefix("/") ? URL(fileURLWithPath: target) : nil
        case .remote: return nil
        }
    }
}

enum LogLevel: Int, Codable, Comparable { case debug, info, warn, hit, error
    static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
    var icon: String { switch self { case .debug: "ellipsis"; case .info: "info.circle"; case .warn: "exclamationmark.triangle"; case .hit: "exclamationmark.shield.fill"; case .error: "xmark.octagon" } }
}

struct LogEntry: Identifiable, Hashable {
    let id = UUID(); let time = Date(); let level: LogLevel; let stage: String; let text: String
}

enum StageID: String, CaseIterable, Identifiable, Codable {
    case mac = "This Mac", local = "Local repositories", remote = "GitHub", ai = "On-device AI triage", summary = "Summary"
    var id: String { rawValue }
    var icon: String { switch self { case .mac: "desktopcomputer"; case .local: "folder"; case .remote: "cloud"; case .ai: "apple.intelligence"; case .summary: "text.alignleft" } }
    var weight: Double { switch self { case .mac: 0.05; case .local: 0.30; case .remote: 0.40; case .ai: 0.20; case .summary: 0.05 } }
}

enum StageState: String, Codable { case pending, running, done, skipped, failed }

struct StageInfo: Identifiable, Equatable {
    let id: StageID
    var state: StageState = .pending
    var done = 0, total = 0
    var detail = ""
    var fraction: Double {
        switch state { case .done, .skipped, .failed: 1; case .pending: 0
        case .running: total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    }
}

enum RunState: Equatable { case idle, running, paused, stopping, finished, stopped }

/// One on-device model call, kept so the user can audit prompts, tokens and latency.
struct AICall: Identifiable, Hashable, Codable {
    var id = UUID()
    let time: Date
    let kind: String            // "triage" | "summary"
    let subject: String
    let instructions: String
    let prompt: String
    var response: String
    var inputTokens: Int
    var outputTokens: Int
    var exactTokens: Bool
    var seconds: Double
    var ok: Bool
    var cached = false
}

struct ScanRecord: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let duration: Double
    let coverage: [String]
    let findings: [Finding]
    let summary: String
    let aiCalls: Int, inputTokens: Int, outputTokens: Int
    var suspicious: Int { findings.filter { $0.level == .malicious }.count }
    var review: Int { findings.filter { $0.level == .review }.count }
}
