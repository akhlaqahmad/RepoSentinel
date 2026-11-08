import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case overview = "Overview", findings = "Findings", activity = "Activity", ai = "AI Insights", history = "History"
    var id: String { rawValue }
    var icon: String { switch self { case .overview: "gauge.with.dots.needle.67percent"; case .findings: "exclamationmark.shield"; case .activity: "list.bullet.rectangle"; case .ai: "apple.intelligence"; case .history: "clock.arrow.circlepath" } }
}

func clock(_ s: TimeInterval) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

struct MainView: View {
    @EnvironmentObject var e: ScanEngine
    @State private var tab: Tab = .overview

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $tab) { t in
                Label(t.rawValue, systemImage: t.icon).badge(badge(t)).tag(t)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                switch tab {
                case .overview: OverviewView(goto: { tab = $0 })
                case .findings: FindingsView()
                case .activity: ActivityView()
                case .ai: AIInsightsView()
                case .history: HistoryView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
        }
        .toolbar { ControlsToolbar() }
        .navigationTitle("RepoSentinel")
    }

    func badge(_ t: Tab) -> Int {
        switch t { case .findings: e.visible(.malicious).count; case .activity: 0; default: 0 }
    }
}

struct ControlsToolbar: ToolbarContent {
    @EnvironmentObject var e: ScanEngine
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            switch e.state {
            case .idle, .finished, .stopped:
                Button { e.start() } label: { Label(e.state == .idle ? "Run checkup" : "Run again", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).help("Start a new checkup (⌘R)")
            case .running:
                Button { e.pause() } label: { Label("Pause", systemImage: "pause.fill") }.help("Pause after in-flight requests finish (⌥⌘P)")
                Button(role: .destructive) { e.stop() } label: { Label("Stop", systemImage: "stop.fill") }.help("Stop the scan (⌘.)")
            case .paused:
                Button { e.resume() } label: { Label("Resume", systemImage: "play.fill") }.buttonStyle(.borderedProminent).help("Resume (⌥⌘P)")
                Button(role: .destructive) { e.stop() } label: { Label("Stop", systemImage: "stop.fill") }
            case .stopping:
                ProgressView().controlSize(.small)
            }
            Button { e.restart() } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
                .disabled(e.state == .idle || e.state == .stopping).help("Stop and start over (⇧⌘R)")
        }
    }
}

struct StatusBar: View {
    @EnvironmentObject var e: ScanEngine
    var body: some View {
        VStack(spacing: 6) {
            if e.isBusy { ProgressView(value: e.overall).progressViewStyle(.linear) }
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(color)
                Text(e.currentAction).lineLimit(1).truncationMode(.middle)
                Spacer()
                if e.state != .idle {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let el = e.elapsed(ctx.date)
                        HStack(spacing: 8) {
                            if e.state == .running, e.overall > 0.03 { Text("~\(clock(el * (1 - e.overall) / e.overall)) left").foregroundStyle(.secondary) }
                            Label(clock(el), systemImage: "stopwatch").labelStyle(.titleAndIcon)
                            if e.isBusy { Text("\(Int(e.overall * 100))%").monospacedDigit() }
                        }.font(.callout.monospacedDigit())
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
        .accessibilityElement(children: .combine)
    }
    var icon: String { switch e.state { case .running: "arrow.triangle.2.circlepath"; case .paused: "pause.circle.fill"; case .stopping: "hourglass"; case .stopped: "stop.circle"; case .finished: "checkmark.circle.fill"; case .idle: "circle.dashed" } }
    var color: Color { switch e.state { case .running: .blue; case .paused: .orange; case .finished: e.visible(.malicious).isEmpty ? .green : .red; default: .secondary } }
}
