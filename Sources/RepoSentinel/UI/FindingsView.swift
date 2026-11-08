import SwiftUI

enum FindingFilter: String, CaseIterable, Identifiable {
    case suspicious = "Suspicious", review = "Review", benign = "Benign", ignored = "Ignored", all = "All"
    var id: String { rawValue }
}

func levelColor(_ l: Level) -> Color { switch l { case .malicious: .red; case .review: .orange; case .benign: .green } }
func levelIcon(_ l: Level) -> String { switch l { case .malicious: "exclamationmark.shield.fill"; case .review: "eye.trianglebadge.exclamationmark"; case .benign: "checkmark.shield" } }

struct FindingsView: View {
    @EnvironmentObject var e: ScanEngine
    @State private var filter: FindingFilter = .suspicious
    @State private var source: Source? = nil
    @State private var query = ""
    @State private var sel: Finding.ID?

    var list: [Finding] {
        var r: [Finding]
        switch filter {
        case .suspicious: r = e.visible(.malicious); case .review: r = e.visible(.review); case .benign: r = e.visible(.benign)
        case .ignored: r = e.ignoredFindings; case .all: r = e.findings
        }
        if let s = source { r = r.filter { $0.source == s } }
        if !query.isEmpty { r = r.filter { ($0.target + $0.file + $0.rule + ($0.verdict?.reason ?? "")).localizedCaseInsensitiveContains(query) } }
        return r.sorted { ($0.isNew ? 0 : 1, $0.target) < ($1.isNew ? 0 : 1, $1.target) }
    }
    func count(_ f: FindingFilter) -> Int {
        switch f { case .suspicious: e.visible(.malicious).count; case .review: e.visible(.review).count; case .benign: e.visible(.benign).count; case .ignored: e.ignoredFindings.count; case .all: e.findings.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $filter) { ForEach(FindingFilter.allCases) { Text("\($0.rawValue) \(count($0))").tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520)
                Menu { Button("All sources") { source = nil }; ForEach(Source.allCases) { s in Button(s.rawValue) { source = s } } }
                    label: { Label(source?.rawValue ?? "All sources", systemImage: "line.3.horizontal.decrease.circle") }.fixedSize()
                Spacer()
            }.padding(12)
            Divider()
            HSplitView {
                List(list, selection: $sel) { f in row(f).tag(f.id) }
                    .frame(minWidth: 320, idealWidth: 420)
                    .overlay { if list.isEmpty { ContentUnavailableView(e.findings.isEmpty ? "No results yet" : "Nothing here", systemImage: "shield", description: Text(e.findings.isEmpty ? "Run a checkup to see findings." : "No \(filter.rawValue.lowercased()) findings.")) } }
                Group {
                    if let f = e.findings.first(where: { $0.id == sel }) { FindingDetail(f: f) }
                    else { ContentUnavailableView("Select a finding", systemImage: "sidebar.right") }
                }.frame(minWidth: 380)
            }
        }
        .searchable(text: $query, prompt: "Search findings")
    }

    func row(_ f: Finding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: levelIcon(f.level)).foregroundStyle(levelColor(f.level)).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text((f.target as NSString).lastPathComponent.isEmpty ? f.target : (f.source == .local ? (f.target as NSString).lastPathComponent : f.target)).fontWeight(.medium).lineLimit(1)
                    if f.isNew { Text("NEW").font(.caption2.bold()).padding(.horizontal, 5).background(.blue, in: Capsule()).foregroundStyle(.white) }
                }
                Text(f.file).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Label(f.source.rawValue, systemImage: f.source.icon); Text("·"); Text(f.rule)
                    if f.branches.count > 1 { Text("· \(f.branches.count) branches") }
                }.font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }.padding(.vertical, 2)
    }
}

struct FindingDetail: View {
    @EnvironmentObject var e: ScanEngine
    let f: Finding
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: levelIcon(f.level)).font(.title).foregroundStyle(levelColor(f.level))
                    VStack(alignment: .leading) { Text(f.rule).font(.headline); Text("\(f.source.rawValue) · \(f.target)").font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                if let v = f.verdict {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(v.reason).textSelection(.enabled)
                            Text("→ \(v.action)").foregroundStyle(.secondary).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    } label: { Label(v.byAI ? "Judged on-device by Apple Intelligence" : "Rule-based", systemImage: v.byAI ? "apple.intelligence" : "checklist") }
                }
                GroupBox("What to do") { Text(IOC.remediation(for: f.rule)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(4) }
                LabeledContent("File") { Text(f.file).font(.callout.monospaced()).textSelection(.enabled) }
                if !f.branches.isEmpty { LabeledContent("Branches") { Text(f.branches.joined(separator: ", ")).font(.callout.monospaced()).textSelection(.enabled) } }
                if !f.excerpt.isEmpty {
                    GroupBox("Matched content") {
                        ScrollView(.horizontal) { Text(f.excerpt).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(6) }
                    }
                    Text("Shown as text only — never executed.").font(.caption).foregroundStyle(.tertiary)
                }
                HStack {
                    if let u = f.localURL { Button { NSWorkspace.shared.activateFileViewerSelecting([u]) } label: { Label("Reveal in Finder", systemImage: "folder") } }
                    if let u = f.url { Button { NSWorkspace.shared.open(u) } label: { Label("Open on GitHub", systemImage: "safari") } }
                    Button { copy(f.localURL?.path ?? f.url?.absoluteString ?? f.target) } label: { Label("Copy path", systemImage: "doc.on.doc") }
                    Spacer()
                    Button { e.toggleIgnore(f) } label: { Label(e.ignored.contains(f.key) ? "Stop ignoring" : "Ignore", systemImage: e.ignored.contains(f.key) ? "eye" : "eye.slash") }
                        .help("Hide this finding in future scans")
                }.controlSize(.small)
            }.padding(18)
        }
    }
    func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
}
