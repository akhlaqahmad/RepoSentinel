import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var e: ScanEngine
    @AppStorage(Pref.scanMac) var scanMac = true
    @AppStorage(Pref.scanLocal) var scanLocal = true
    @AppStorage(Pref.scanRemote) var scanRemote = true
    let goto: (Tab) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                if let n = e.aiNote { warn(n) }
                if e.state == .idle || !e.isBusy { scope }
                stagesCard
                if e.isBusy, !e.activeItems.isEmpty { activeCard }
                if !e.summary.isEmpty { summaryCard }
            }.padding(20)
        }
    }

    var hero: some View {
        let bad = e.visible(.malicious).count, rev = e.visible(.review).count
        let done = e.state == .finished
        return HStack(alignment: .center, spacing: 18) {
            Image(systemName: heroIcon(done, bad)).font(.system(size: 52)).foregroundStyle(heroColor(done, bad)).symbolEffect(.pulse, isActive: e.state == .running)
            VStack(alignment: .leading, spacing: 4) {
                Text(heroTitle(done, bad)).font(.title.weight(.semibold))
                Text(e.state == .idle ? "Checks this Mac, your local git repositories and your GitHub repos for the PolinRider worm. Everything runs on your Mac." : e.currentAction)
                    .foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if e.state != .idle {
                HStack(spacing: 10) {
                    tile("Suspicious", bad, .red, .findings); tile("Review", rev, .orange, .findings)
                    tile("Benign", e.visible(.benign).count, .green, .findings); tile("Ignored", e.ignoredFindings.count, .gray, .findings)
                }
            }
        }.padding(18).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
    func tile(_ t: String, _ n: Int, _ c: Color, _ dest: Tab) -> some View {
        Button { goto(dest) } label: {
            VStack { Text("\(n)").font(.title2.monospacedDigit().weight(.bold)).foregroundStyle(c); Text(t).font(.caption).foregroundStyle(.secondary) }
                .frame(width: 74).padding(.vertical, 8).background(.background, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel("\(n) \(t)")
    }
    func heroIcon(_ done: Bool, _ bad: Int) -> String { e.state == .idle ? "shield" : done ? (bad == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill") : e.state == .stopped ? "shield.slash" : "shield.lefthalf.filled" }
    func heroColor(_ done: Bool, _ bad: Int) -> Color { e.state == .idle || e.state == .stopped ? .secondary : done ? (bad == 0 ? .green : .red) : .blue }
    func heroTitle(_ done: Bool, _ bad: Int) -> String {
        switch e.state { case .idle: "Ready for a checkup"; case .running: "Scanning…"; case .paused: "Paused"; case .stopping: "Stopping…"
        case .stopped: "Stopped — partial results"; case .finished: bad == 0 ? "All clear" : "\(bad) suspicious finding\(bad == 1 ? "" : "s")" }
    }
    func warn(_ s: String) -> some View {
        HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(s); Spacer()
            Button("Open Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!) } }
            .padding(12).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    var scope: some View {
        GroupBox("What to scan") {
            HStack(spacing: 24) {
                Toggle(isOn: $scanMac) { Label("This Mac", systemImage: "desktopcomputer") }
                Toggle(isOn: $scanLocal) { Label("Local repos", systemImage: "folder") }
                Toggle(isOn: $scanRemote) { Label("GitHub", systemImage: "cloud") }
                Spacer()
                Text("Folders & options: Settings (⌘,)").font(.caption).foregroundStyle(.secondary)
            }.toggleStyle(.checkbox).padding(6)
        }
    }

    var stagesCard: some View {
        GroupBox("Progress") {
            VStack(spacing: 0) {
                ForEach(e.stages) { s in
                    HStack(spacing: 12) {
                        Image(systemName: s.id.icon).frame(width: 22).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(s.id.rawValue).fontWeight(.medium); Spacer()
                                if s.state == .running, s.total > 0 { Text("\(s.done)/\(s.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) } }
                            if s.state == .running { ProgressView(value: s.total > 0 ? s.fraction : nil).controlSize(.small) }
                            if !s.detail.isEmpty { Text(s.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                        }
                        glyph(s.state).frame(width: 22)
                    }.padding(.vertical, 8)
                    if s.id != StageID.allCases.last { Divider() }
                }
            }.padding(.horizontal, 6)
        }
    }
    @ViewBuilder func glyph(_ s: StageState) -> some View {
        switch s {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running: if e.state == .paused { Image(systemName: "pause.circle.fill").foregroundStyle(.orange) } else { ProgressView().controlSize(.small) }
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    var activeCard: some View {
        GroupBox("Working on now") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(e.activeItems.prefix(8).enumerated()), id: \.offset) { _, i in
                    HStack { ProgressView().controlSize(.mini); Text(i).font(.callout.monospaced()).lineLimit(1) } }
                if e.activeItems.count > 8 { Text("+ \(e.activeItems.count - 8) more in parallel").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }

    var summaryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(e.summary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(e.summary, forType: .string) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Button { saveFile("RepoSentinel-report.md", e.markdownReport().data(using: .utf8)!) } label: { Label("Export report…", systemImage: "square.and.arrow.up") }
                    Spacer()
                    Button { goto(.ai) } label: { Label("See prompts & cost", systemImage: "apple.intelligence") }.buttonStyle(.link)
                }.controlSize(.small)
            }.padding(6)
        } label: { Label("Summary — written on-device", systemImage: "apple.intelligence") }
    }
}
