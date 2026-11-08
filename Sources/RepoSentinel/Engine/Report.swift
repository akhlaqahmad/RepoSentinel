import Foundation

extension ScanEngine {
    func markdownReport() -> String {
        var s = "# RepoSentinel report\n\n"
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        s += "- Date: \(f.string(from: startedAt ?? Date()))\n- Duration: \(Int(elapsed()))s\n- Scanned: \(coverage.joined(separator: ", "))\n"
        s += "- AI: on-device Apple Foundation Models · \(aiCalls.count) calls · \(inputTokens) in / \(outputTokens) out tokens · cost $0.00\n\n"
        if !summary.isEmpty { s += "## Summary\n\n\(summary)\n\n" }
        for (title, lvl) in [("Suspicious", Level.malicious), ("Needs review", .review), ("Benign", .benign)] {
            let items = visible(lvl); s += "## \(title) (\(items.count))\n\n"
            for x in items {
                s += "- **\(x.target)** — `\(x.file)` — \(x.rule)" + (x.branches.isEmpty ? "" : " (branches: \(x.branches.prefix(5).joined(separator: ", "))\(x.branches.count > 5 ? "…" : ""))") + "\n"
                if let v = x.verdict { s += "  - \(v.reason) → \(v.action)\n" }
            }
            s += "\n"
        }
        return s
    }
    func jsonReport() -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(ScanRecord(date: startedAt ?? Date(), duration: elapsed(), coverage: coverage, findings: findings, summary: summary,
                                           aiCalls: aiCalls.count, inputTokens: inputTokens, outputTokens: outputTokens))) ?? Data()
    }
}
