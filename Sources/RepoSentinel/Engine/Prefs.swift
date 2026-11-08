import Foundation

enum Pref {
    static let scanMac = "scanMac", scanLocal = "scanLocal", scanRemote = "scanRemote"
    static let roots = "scanRoots", extraSkip = "extraSkipDirs", ghConcurrency = "ghConcurrency"
    static let aiEnabled = "aiEnabled", aiInstructions = "aiInstructions", rateIn = "rateIn", rateOut = "rateOut"
    static let notify = "notifyOnFinish", autoScan = "autoScanOnLaunch"

    static func register() {
        UserDefaults.standard.register(defaults: [
            scanMac: true, scanLocal: true, scanRemote: true, ghConcurrency: 6,
            aiEnabled: true, aiInstructions: "", rateIn: 3.0, rateOut: 15.0, notify: true, autoScan: false,
            roots: [NSHomeDirectory()], extraSkip: "",
        ])
    }
}

/// Small JSON store in ~/Library/Application Support/RepoSentinel.
enum Store {
    static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RepoSentinel")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: d)
    }
    static func save<T: Encodable>(_ v: T, _ name: String) {
        if ProcessInfo.processInfo.environment["RS_NO_PERSIST"] != nil { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(v) { try? d.write(to: dir.appendingPathComponent(name), options: .atomic) }
    }
}

actor Gate {
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func pause() { paused = true }
    func resume() { paused = false; waiters.forEach { $0.resume() }; waiters = [] }
    func wait() async { if paused { await withCheckedContinuation { waiters.append($0) } } }
}
