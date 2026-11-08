import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class ScanEngine: ObservableObject {
    @Published var state: RunState = .idle
    @Published var stages: [StageInfo] = StageID.allCases.map { StageInfo(id: $0) }
    @Published var findings: [Finding] = []
    @Published var log: [LogEntry] = []
    @Published var aiCalls: [AICall] = []
    @Published var summary = ""
    @Published var currentAction = "Ready to scan"
    @Published var activeItems: [String] = []
    @Published var history: [ScanRecord] = (Store.load("history.json", as: [ScanRecord].self) ?? [])
    @Published var ignored: Set<String> = Set(Store.load("ignored.json", as: [String].self) ?? [])
    @Published var coverage: [String] = []
    let aiNote = AIService.availability()

    private let gate = Gate()
    private var task: Task<Void, Never>?
    private var base: TimeInterval = 0, segStart: Date?
    private(set) var startedAt: Date?
    private lazy var ai = AIService(instructions: UserDefaults.standard.string(forKey: Pref.aiInstructions) ?? "")

    // MARK: derived
    var isBusy: Bool { state == .running || state == .paused || state == .stopping }
    func elapsed(_ now: Date = Date()) -> TimeInterval { base + (segStart.map { now.timeIntervalSince($0) } ?? 0) }
    var overall: Double {
        let on = stages.filter { $0.state != .skipped }
        let w = on.reduce(0) { $0 + $1.id.weight }
        return w == 0 ? 0 : on.reduce(0) { $0 + $1.id.weight * $1.fraction } / w
    }
    func visible(_ l: Level) -> [Finding] { findings.filter { $0.level == l && !ignored.contains($0.key) } }
    var ignoredFindings: [Finding] { findings.filter { ignored.contains($0.key) } }
    var inputTokens: Int { aiCalls.reduce(0) { $0 + $1.inputTokens } }
    var outputTokens: Int { aiCalls.reduce(0) { $0 + $1.outputTokens } }
    var aiSeconds: Double { aiCalls.reduce(0) { $0 + $1.seconds } }
    var cloudEquivalent: Double {
        let d = UserDefaults.standard
        return Double(inputTokens) / 1e6 * d.double(forKey: Pref.rateIn) + Double(outputTokens) / 1e6 * d.double(forKey: Pref.rateOut)
    }

    // MARK: controls
    func start() {
        guard !isBusy else { return }
        findings = []; log = []; aiCalls = []; summary = ""; coverage = []; activeItems = []
        stages = StageID.allCases.map { StageInfo(id: $0) }
        base = 0; startedAt = Date(); segStart = Date(); state = .running
        Task { await ai.setInstructions(UserDefaults.standard.string(forKey: Pref.aiInstructions) ?? "") }
        task = Task { [weak self] in await self?.runAll() }
    }
    func pause() {
        guard state == .running else { return }
        base = elapsed(); segStart = nil; state = .paused
        Task { await gate.pause() }
        addLog(.warn, nil, "Paused — in-flight requests will finish, then work stops")
        currentAction = "Paused"
    }
    func resume() {
        guard state == .paused else { return }
        segStart = Date(); state = .running
        Task { await gate.resume() }
        addLog(.info, nil, "Resumed")
    }
    func stop() {
        guard state == .running || state == .paused else { return }
        state = .stopping; currentAction = "Stopping…"
        task?.cancel()
        Task { await gate.resume() }
    }
    func restart() {
        let t = task
        if isBusy { stop() }
        Task { _ = await t?.value; start() }
    }
    func toggleIgnore(_ f: Finding) {
        if ignored.contains(f.key) { ignored.remove(f.key) } else { ignored.insert(f.key) }
        Store.save(Array(ignored), "ignored.json")
    }
    func clearHistory() { history = []; Store.save([ScanRecord](), "history.json") }
    func clearIgnored() { ignored = []; Store.save([String](), "ignored.json") }

    // MARK: event sinks (main actor)
    nonisolated private func post(_ f: @escaping @MainActor (ScanEngine) -> Void) {
        DispatchQueue.main.async { [weak self] in guard let self else { return }; MainActor.assumeIsolated { f(self) } }
    }
    func addLog(_ l: LogLevel, _ s: StageID?, _ t: String) {
        log.append(LogEntry(level: l, stage: s?.rawValue ?? "", text: t))
        if log.count > 6000 { log.removeFirst(1000) }
        if l >= .info && l != .hit { currentAction = t }
    }
    private func setStage(_ id: StageID, _ mutate: (inout StageInfo) -> Void) {
        if let i = stages.firstIndex(where: { $0.id == id }) { mutate(&stages[i]) }
    }
    private func setActive(_ item: String, _ on: Bool) {
        if on { activeItems.append(item) } else { activeItems.removeAll { $0 == item } }
    }
    private func ctx(_ stage: StageID) -> Ctx {
        let d = UserDefaults.standard
        let extra = (d.string(forKey: Pref.extraSkip) ?? "").split(whereSeparator: { ", \n".contains($0) }).map(String.init)
        var c = Ctx(
            log: { [weak self] l, t in self?.post { $0.addLog(l, stage, t) } },
            found: { [weak self] f in self?.post { $0.findings.append(f) } },
            progress: { [weak self] done, total, det in self?.post { e in e.setStage(stage) { $0.done = done; if total > 0 { $0.total = total }; $0.detail = det } } },
            active: { [weak self] i, on in self?.post { $0.setActive(i, on) } },
            checkpoint: { [gate] in try Task.checkCancellation(); await gate.wait(); try Task.checkCancellation() })
        c.skipDirs = IOC.defaultSkip.union(extra)
        c.roots = ((d.array(forKey: Pref.roots) as? [String]) ?? [NSHomeDirectory()]).map { URL(fileURLWithPath: $0) }
        c.concurrency = max(1, min(16, d.integer(forKey: Pref.ghConcurrency)))
        return c
    }

    // MARK: the run
    private func runAll() async {
        let d = UserDefaults.standard
        do {
            try await stage(.mac, enabled: d.bool(forKey: Pref.scanMac)) { c in
                try await MacCheck.run(c); self.post { $0.coverage.append("Mac persistence (6 checks)") }
            }
            try await stage(.local, enabled: d.bool(forKey: Pref.scanLocal)) { c in
                let repos = try await LocalScan.discover(c)
                c.progress(0, repos.count, "Scanning \(repos.count) repositories")
                let n = Counter()
                try await forEachConcurrent(repos, limit: 4) { r in
                    try await c.checkpoint(); c.active(r.lastPathComponent, true); defer { c.active(r.lastPathComponent, false) }
                    c.log(.debug, "Scanning \(r.path)")
                    _ = try await LocalScan.scan(repo: r, c)
                    c.progress(n.inc(), repos.count, r.lastPathComponent)
                }
                self.post { $0.coverage.append("\(repos.count) local repos") }
            }
            try await stage(.remote, enabled: d.bool(forKey: Pref.scanRemote)) { c in
                let n = try await GitHubScan.run(c)
                self.post { $0.coverage.append("\(n) GitHub repos (all branches)") }
            }
            try await triage()
            try await writeSummary()
            finish()
        } catch is CancellationError {
            state = .stopped; segStart = nil; base = elapsed(); activeItems = []
            stages = stages.map { var s = $0; if s.state == .running { s.state = .pending; s.detail = "Stopped" }; return s }
            addLog(.warn, nil, "Stopped by user — partial results kept, not saved to history")
            currentAction = "Stopped"
        } catch {
            state = .stopped; addLog(.error, nil, "Scan failed: \(error.localizedDescription)")
        }
    }

    private func stage(_ id: StageID, enabled: Bool, _ body: @escaping (Ctx) async throws -> Void) async throws {
        try Task.checkCancellation()
        guard enabled else { setStage(id) { $0.state = .skipped; $0.detail = "Turned off" }; addLog(.info, id, "Skipped (turned off in options)"); return }
        setStage(id) { $0.state = .running }; addLog(.info, id, "Starting \(id.rawValue)")
        let t0 = Date()
        do {
            try await body(ctx(id))
            setStage(id) { $0.state = .done; $0.done = max($0.done, $0.total); $0.detail = String(format: "Done in %.1fs", Date().timeIntervalSince(t0)) }
            addLog(.info, id, String(format: "Finished %@ in %.1fs", id.rawValue, Date().timeIntervalSince(t0)))
        } catch let e as ScanSkip {
            setStage(id) { $0.state = .skipped; $0.detail = e.reason }; coverage.append("\(id.rawValue) skipped (\(e.reason))")
        } catch is CancellationError { throw CancellationError() }
        catch { setStage(id) { $0.state = .failed; $0.detail = error.localizedDescription }; addLog(.error, id, "\(id.rawValue) failed: \(error.localizedDescription)") }
    }

    private func triage() async throws {
        let useAI = UserDefaults.standard.bool(forKey: Pref.aiEnabled) && aiNote == nil
        var groups: [String: [Int]] = [:]
        for (i, f) in findings.enumerated() where f.verdict == nil { groups[f.rule + "|" + f.excerpt, default: []].append(i) }
        guard useAI, !groups.isEmpty else {
            let why = aiNote ?? (groups.isEmpty ? "Nothing to triage" : "AI turned off")
            for (_, idx) in groups { for i in idx {
                let benign = findings[i].rule.hasPrefix("gitignore")
                findings[i].verdict = Verdict(level: benign ? .benign : .malicious, reason: benign ? "Leftover ignore lines only." : "Not judged by AI (\(why)); treated as suspicious.", action: IOC.remediation(for: findings[i].rule), byAI: false)
            } }
            setStage(.ai) { $0.state = .skipped; $0.detail = why }; addLog(.info, .ai, "AI triage skipped: \(why)")
            return
        }
        setStage(.ai) { $0.state = .running; $0.total = groups.count }
        addLog(.info, .ai, "On-device model triaging \(groups.count) distinct hit(s) covering \(findings.filter { $0.verdict == nil }.count) finding(s)")
        let ctx = self.ctx(.ai)
        let sink: @Sendable (AICall) -> Void = { [weak self] c in self?.post { $0.aiCalls.append(c) } }
        var n = 0
        for (key, idx) in groups.sorted(by: { $0.value.count > $1.value.count }) {
            try await ctx.checkpoint()
            let f = findings[idx[0]]
            currentAction = "AI reading \(f.file)…"
            let v = await ai.verdict(for: f, log: sink)
            for i in idx { findings[i].verdict = v }
            n += 1
            setStage(.ai) { $0.done = n; $0.detail = "\(f.file)" }
            addLog(v.level == .malicious ? .hit : .info, .ai, "\(n)/\(groups.count) \(f.file): \(v.level.rawValue) — \(v.reason)" + (idx.count > 1 ? " (applied to \(idx.count) similar hits)" : ""))
            _ = key
        }
        setStage(.ai) { $0.state = .done }
    }

    private func writeSummary() async throws {
        try await gate.wait(); try Task.checkCancellation()
        setStage(.summary) { $0.state = .running }
        let cov = coverage.isEmpty ? "nothing scanned" : coverage.joined(separator: ", ")
        let bad = visible(.malicious).count, rev = visible(.review).count
        if UserDefaults.standard.bool(forKey: Pref.aiEnabled), aiNote == nil, !aiCalls.isEmpty || !findings.isEmpty {
            addLog(.info, .summary, "Asking the on-device model to write the summary")
            summary = await ai.summary(findings: findings.filter { !ignored.contains($0.key) }, coverage: cov, log: { [weak self] c in self?.post { $0.aiCalls.append(c) } })
        } else {
            summary = bad == 0 ? "No suspicious files found. Scanned: \(cov)." : "\(bad) suspicious finding(s), \(rev) to review. Scanned: \(cov)."
        }
        setStage(.summary) { $0.state = .done }
    }

    private func finish() {
        let prev = Set((history.first?.findings ?? []).map(\.key))
        if !history.isEmpty { for i in findings.indices { findings[i].isNew = !prev.contains(findings[i].key) } }
        segStart = nil; base = elapsed(); state = .finished; activeItems = []
        let rec = ScanRecord(date: Date(), duration: base, coverage: coverage, findings: findings, summary: summary,
                             aiCalls: aiCalls.count, inputTokens: inputTokens, outputTokens: outputTokens)
        history = Array(([rec] + history).prefix(30)); Store.save(history, "history.json")
        let bad = visible(.malicious).count
        currentAction = bad == 0 ? "Done — nothing suspicious" : "Done — \(bad) suspicious"
        addLog(.info, nil, currentAction)
        if UserDefaults.standard.bool(forKey: Pref.notify) { notify(bad: bad, review: visible(.review).count) }
    }

    private func notify(bad: Int, review: Int) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let m = UNMutableNotificationContent(); m.title = bad == 0 ? "RepoSentinel: all clear" : "RepoSentinel: \(bad) suspicious finding(s)"
            m.body = review > 0 ? "\(review) item(s) need review." : "Scan complete."; if bad > 0 { m.sound = .default }
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: m, trigger: nil))
        }
    }
}
