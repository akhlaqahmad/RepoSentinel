import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var e: ScanEngine
    @State private var minLevel: LogLevel = .info
    @State private var query = ""
    @State private var follow = true
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    var rows: [LogEntry] {
        e.log.filter { $0.level >= minLevel && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.stage.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Detail", selection: $minLevel) {
                    Text("Verbose").tag(LogLevel.debug); Text("Normal").tag(LogLevel.info); Text("Warnings").tag(LogLevel.warn); Text("Hits & errors").tag(LogLevel.hit)
                }.pickerStyle(.segmented).frame(maxWidth: 420)
                Toggle("Follow", isOn: $follow).toggleStyle(.switch).controlSize(.small)
                Spacer()
                Text("\(rows.count) of \(e.log.count) events").font(.caption).foregroundStyle(.secondary)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { saveFile("RepoSentinel-log.txt", text.data(using: .utf8)!) } label: { Label("Save…", systemImage: "square.and.arrow.down") }
            }.padding(12).controlSize(.small)
            Divider()
            ScrollViewReader { proxy in
                List(rows) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Self.fmt.string(from: r.time)).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        Image(systemName: r.level.icon).foregroundStyle(color(r.level)).frame(width: 16)
                        if !r.stage.isEmpty { Text(r.stage).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1).background(.quaternary, in: Capsule()) }
                        Text(r.text).font(.callout).foregroundStyle(r.level == .debug ? .secondary : .primary).textSelection(.enabled)
                    }.id(r.id).listRowSeparator(.hidden)
                }
                .onChange(of: e.log.count) { if follow, let last = rows.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .overlay { if e.log.isEmpty { ContentUnavailableView("No activity yet", systemImage: "list.bullet.rectangle", description: Text("Every file, repo, branch and AI call will be listed here while a scan runs.")) } }
            }
        }
        .searchable(text: $query, prompt: "Filter activity")
    }
    var text: String { rows.map { "\(Self.fmt.string(from: $0.time)) [\($0.level)] \($0.stage.isEmpty ? "" : "\($0.stage): ")\($0.text)" }.joined(separator: "\n") }
    func color(_ l: LogLevel) -> Color { switch l { case .debug: .secondary; case .info: .blue; case .warn: .orange; case .hit, .error: .red } }
}
