import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var e: ScanEngine
    @AppStorage(Pref.notify) var notify = true
    @AppStorage(Pref.autoScan) var autoScan = false
    @AppStorage(Pref.ghConcurrency) var gh = 6
    @AppStorage(Pref.extraSkip) var extraSkip = ""
    @AppStorage(Pref.aiEnabled) var aiOn = true
    @AppStorage(Pref.aiInstructions) var instr = ""
    @AppStorage(Pref.rateIn) var rateIn = 3.0
    @AppStorage(Pref.rateOut) var rateOut = 15.0
    @State private var roots: [String] = (UserDefaults.standard.array(forKey: Pref.roots) as? [String]) ?? [NSHomeDirectory()]

    var body: some View {
        TabView {
            Form {
                Toggle("Run a checkup when the app opens", isOn: $autoScan)
                Toggle("Notify me when a scan finishes", isOn: $notify)
                Stepper("GitHub requests in parallel: \(gh)", value: $gh, in: 1...16)
                Text("Lower this if GitHub starts rate-limiting you.").font(.caption).foregroundStyle(.secondary)
            }.padding().tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Folders searched for git repositories") {
                    List { ForEach(roots, id: \.self) { r in HStack { Image(systemName: "folder"); Text(r); Spacer()
                        Button { roots.removeAll { $0 == r }; save() } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel("Remove \(r)") } } }.frame(height: 120)
                    HStack { Button("Add folder…") { add() }; Button("Reset to Home") { roots = [NSHomeDirectory()]; save() } }
                }
                TextField("Extra folder names to skip (comma separated)", text: $extraSkip)
                Text("Always skipped: node_modules, Library, build, dist, Pods, caches and similar.").font(.caption).foregroundStyle(.secondary)
            }.padding().tabItem { Label("Scope", systemImage: "folder.badge.gearshape") }

            Form {
                Toggle("Use on-device AI to triage findings and write the summary", isOn: $aiOn)
                if let n = e.aiNote { Text(n).foregroundStyle(.orange) } else { Label("Apple Intelligence model is ready", systemImage: "checkmark.circle").foregroundStyle(.green) }
                Section("Triage instructions (system prompt)") {
                    TextEditor(text: Binding(get: { instr.isEmpty ? AIDefaults.triageInstructions : instr }, set: { instr = $0 }))
                        .font(.system(.callout, design: .monospaced)).frame(height: 160).border(.quaternary)
                    Button("Reset to default") { instr = "" }
                }
                Section("Cloud-equivalent cost (illustrative only)") {
                    HStack { Text("$ per 1M input tokens"); TextField("", value: $rateIn, format: .number).frame(width: 70)
                        Text("$ per 1M output tokens"); TextField("", value: $rateOut, format: .number).frame(width: 70) }
                    Text("On-device inference costs you nothing. These rates only power the comparison on the AI Insights page.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding().tabItem { Label("AI", systemImage: "apple.intelligence") }

            Form {
                LabeledContent("Scan history") { Text("\(e.history.count) scans"); Button("Clear") { e.clearHistory() } }
                LabeledContent("Ignored findings") { Text("\(e.ignored.count)"); Button("Clear") { e.clearIgnored() } }
                Button("Show data folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.dir]) }
                Text("RepoSentinel is read-only: it never modifies, deletes or uploads your files or repositories. GitHub access uses your existing `gh` login.").font(.caption).foregroundStyle(.secondary)
            }.padding().tabItem { Label("Data", systemImage: "internaldrive") }
        }.frame(width: 560, height: 460)
    }
    func save() { UserDefaults.standard.set(roots, forKey: Pref.roots) }
    func add() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        if p.runModal() == .OK { for u in p.urls where !roots.contains(u.path) { roots.append(u.path) }; save() }
    }
}
