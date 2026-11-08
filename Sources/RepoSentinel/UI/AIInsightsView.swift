import SwiftUI

struct AIInsightsView: View {
    @EnvironmentObject var e: ScanEngine
    @AppStorage(Pref.rateIn) var rateIn = 3.0
    @AppStorage(Pref.rateOut) var rateOut = 15.0
    @State private var sel: AICall.ID?

    var body: some View {
        VStack(spacing: 0) {
            stats.padding(14)
            Divider()
            HSplitView {
                List(e.aiCalls.reversed(), selection: $sel) { c in
                    HStack {
                        Image(systemName: c.ok ? (c.kind == "summary" ? "text.alignleft" : "checkmark.seal") : "xmark.octagon").foregroundStyle(c.ok ? Color.accentColor : .red)
                        VStack(alignment: .leading) {
                            Text(c.subject).lineLimit(1).truncationMode(.middle)
                            Text("\(c.inputTokens) in · \(c.outputTokens) out · \(String(format: "%.2fs", c.seconds))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }.tag(c.id)
                }
                .frame(minWidth: 280, idealWidth: 330)
                .overlay { if e.aiCalls.isEmpty { ContentUnavailableView("No AI calls yet", systemImage: "apple.intelligence", description: Text("Each call to the on-device model — prompt, response, tokens, time — appears here.")) } }
                Group {
                    if let c = e.aiCalls.first(where: { $0.id == sel }) { callDetail(c) } else { templates }
                }.frame(minWidth: 420)
            }
        }
    }

    var stats: some View {
        HStack(spacing: 10) {
            stat("Model calls", "\(e.aiCalls.count)", "apple.intelligence")
            stat("Input tokens", "\(e.inputTokens)", "arrow.down.circle")
            stat("Output tokens", "\(e.outputTokens)", "arrow.up.circle")
            stat("Model time", String(format: "%.1fs", e.aiSeconds), "timer")
            stat("Your cost", "$0.00", "leaf", tint: .green, help: "Runs on the Mac's Neural Engine/GPU. No API fees, no data leaves the device.")
            stat("Cloud-equivalent", String(format: "$%.4f", e.cloudEquivalent), "cloud", help: "What the same tokens would cost on a cloud API at $\(rateIn, default: "%.2f")/M input and $\(rateOut, default: "%.2f")/M output. Illustrative — change rates in Settings → AI.")
        }
    }
    func stat(_ t: String, _ v: String, _ icon: String, tint: Color = .primary, help: String = "") -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(t, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(tint)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10)).help(help)
    }

    func block(_ title: String, _ text: String, icon: String) -> some View {
        GroupBox {
            ScrollView { Text(text).font(.system(.callout, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                .frame(maxHeight: 220)
        } label: {
            HStack { Label(title, systemImage: icon); Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy").accessibilityLabel("Copy \(title)") }
        }
    }
    func callDetail(_ c: AICall) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            HStack { Text(c.subject).font(.headline); Spacer()
                Text(c.exactTokens ? "exact token counts" : "estimated tokens").font(.caption).padding(.horizontal, 6).background(.quaternary, in: Capsule()) }
            Text("\(c.kind) · \(c.time.formatted(date: .omitted, time: .standard)) · \(c.inputTokens) in / \(c.outputTokens) out · \(String(format: "%.2fs", c.seconds))").font(.caption).foregroundStyle(.secondary)
            block("System instructions", c.instructions, icon: "gearshape")
            block("Prompt sent to model", c.prompt, icon: "text.bubble")
            block("Response", c.response, icon: "sparkles")
        }.padding(16) }
    }
    var templates: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            Text("Prompts in use").font(.headline)
            Text("Select a call on the left to see exactly what was sent. These are the standing instructions; edit them in Settings → AI.").font(.callout).foregroundStyle(.secondary)
            block("Triage instructions", UserDefaults.standard.string(forKey: Pref.aiInstructions).flatMap { $0.isEmpty ? nil : $0 } ?? AIDefaults.triageInstructions, icon: "checkmark.seal")
            block("Summary instructions", AIDefaults.summaryInstructions, icon: "text.alignleft")
        }.padding(16) }
    }
}
