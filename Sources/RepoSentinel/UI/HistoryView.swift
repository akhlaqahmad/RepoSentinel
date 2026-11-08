import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var e: ScanEngine
    @State private var sel: ScanRecord.ID?

    var body: some View {
        HSplitView {
            List(e.history, selection: $sel) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.date.formatted(date: .abbreviated, time: .shortened)).fontWeight(.medium)
                    HStack(spacing: 8) {
                        Label("\(r.suspicious)", systemImage: "exclamationmark.shield.fill").foregroundStyle(r.suspicious == 0 ? Color.secondary : .red)
                        Label("\(r.review)", systemImage: "eye").foregroundStyle(.orange)
                        Text(clock(r.duration)).foregroundStyle(.secondary)
                    }.font(.caption.monospacedDigit())
                }.tag(r.id)
            }
            .frame(minWidth: 240, idealWidth: 280)
            .overlay { if e.history.isEmpty { ContentUnavailableView("No past scans", systemImage: "clock.arrow.circlepath", description: Text("Completed scans are kept here (last 30).")) } }
            Group {
                if let i = e.history.firstIndex(where: { $0.id == sel }) { detail(e.history[i], older: i + 1 < e.history.count ? e.history[i + 1] : nil) }
                else { ContentUnavailableView("Select a scan", systemImage: "sidebar.right") }
            }.frame(minWidth: 380)
        }
    }

    func detail(_ r: ScanRecord, older: ScanRecord?) -> some View {
        let now = Set(r.findings.filter { $0.level != .benign }.map(\.key)), before = Set((older?.findings ?? []).filter { $0.level != .benign }.map(\.key))
        return ScrollView { VStack(alignment: .leading, spacing: 12) {
            Text(r.date.formatted(date: .complete, time: .shortened)).font(.headline)
            Text("Scanned: \(r.coverage.joined(separator: ", ")) · \(clock(r.duration)) · AI \(r.aiCalls) calls, \(r.inputTokens + r.outputTokens) tokens, $0.00")
                .font(.callout).foregroundStyle(.secondary)
            if older != nil {
                HStack(spacing: 24) {
                    Label("\(now.subtracting(before).count) new since previous", systemImage: "plus.circle").foregroundStyle(now.subtracting(before).isEmpty ? Color.secondary : .red)
                    Label("\(before.subtracting(now).count) resolved", systemImage: "checkmark.circle").foregroundStyle(.green)
                }
            }
            if !r.summary.isEmpty { GroupBox("Summary") { Text(r.summary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(4) } }
            GroupBox("Suspicious & review (\(r.suspicious + r.review))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(r.findings.filter { $0.level != .benign }) { f in
                        HStack(alignment: .top) { Image(systemName: levelIcon(f.level)).foregroundStyle(levelColor(f.level))
                            VStack(alignment: .leading) { Text(f.target).lineLimit(1); Text("\(f.file) — \(f.rule)").font(.caption).foregroundStyle(.secondary) } }
                    }
                    if r.suspicious + r.review == 0 { Text("Nothing.").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
        }.padding(16) }
    }
}
