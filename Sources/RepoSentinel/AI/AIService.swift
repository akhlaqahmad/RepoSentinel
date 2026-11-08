import Foundation
import FoundationModels

@Generable
struct AIVerdict {
    @Guide(description: "True only if the excerpt shows obfuscated code, remote payload loading, crypto-RPC endpoints, auto-run hooks, or a known dropper pattern")
    var malicious: Bool
    @Guide(description: "One short sentence explaining why")
    var reason: String
    @Guide(description: "One short sentence: the concrete next step for the developer")
    var action: String
}

enum AIDefaults {
    static let triageInstructions = """
    You are a malware triage assistant for a developer's Mac and Git repositories. \
    The known threat is the PolinRider / EtherHiding worm: it hides obfuscated JavaScript in *.config.js, root api.js, \
    package.json scripts (`node api.js &&`), .vscode/tasks.json (folderOpen), fake fa-solid font files, and build.gradle, \
    padding lines with 100+ spaces, and fetches payloads from blockchain RPC endpoints (trongrid, bsc-dataseed, blastapi). \
    Leftover .gitignore lines naming temp_*push.bat or branch_structure.json are harmless. \
    Git hooks from husky, lefthook or git-lfs are normal. \
    Judge only from the excerpt given. Be conservative: say malicious only with concrete evidence.
    """
    static let summaryInstructions = "You write concise security checkup reports for a developer. Plain text, no markdown headers, under 150 words."
}

/// On-device Apple Foundation Models. Nothing leaves the Mac, so there is no per-call fee.
actor AIService {
    var triageInstructions: String
    init(instructions: String) { triageInstructions = instructions.isEmpty ? AIDefaults.triageInstructions : instructions }

    nonisolated static func availability() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let r):
            switch r {
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is turned off. Enable it in System Settings → Apple Intelligence & Siri."
            case .deviceNotEligible: return "This Mac does not support Apple Intelligence."
            case .modelNotReady: return "The on-device model is still downloading. Try again in a few minutes."
            default: return "The on-device model is unavailable (\(r))."
            }
        }
    }

    func setInstructions(_ s: String) { triageInstructions = s.isEmpty ? AIDefaults.triageInstructions : s }

    func triagePrompt(for f: Finding) -> String {
        let where_ = f.branches.isEmpty ? "" : "\nPresent on \(f.branches.count) branch(es)"
        return "Rule hit: \(f.rule)\nFile: \(f.file)\(where_)\nExcerpt:\n\(String(f.excerpt.prefix(700)))"
    }

    func verdict(for f: Finding, log: @Sendable (AICall) -> Void) async -> Verdict {
        if f.rule.hasPrefix("gitignore IOC") {
            return Verdict(level: .benign, reason: "Leftover ignore lines only; no executable payload.", action: "Optionally delete those lines.", byAI: false)
        }
        let prompt = triagePrompt(for: f), instr = triageInstructions
        let session = LanguageModelSession(instructions: instr)
        let t0 = Date()
        do {
            let r = try await session.respond(to: prompt, generating: AIVerdict.self, options: GenerationOptions(sampling: .greedy))
            var (i, o, exact) = estimate(prompt, instr, "\(r.content)")
            if #available(macOS 27.0, *) { i = r.usage.input.totalTokenCount; o = r.usage.output.totalTokenCount; exact = true }
            log(AICall(time: t0, kind: "triage", subject: "\(f.target) · \(f.file)", instructions: instr, prompt: prompt,
                       response: "malicious: \(r.content.malicious)\nreason: \(r.content.reason)\naction: \(r.content.action)",
                       inputTokens: i, outputTokens: o, exactTokens: exact, seconds: Date().timeIntervalSince(t0), ok: true))
            if IOC.isStrong(f) && !r.content.malicious {
                return Verdict(level: .malicious, reason: "Matches a known worm fingerprint, so the rule-based verdict stands. (AI disagreed: \(r.content.reason))", action: IOC.remediation(for: f.rule), byAI: false)
            }
            return Verdict(level: r.content.malicious ? .malicious : .benign, reason: r.content.reason, action: r.content.action, byAI: true)
        } catch {
            log(AICall(time: t0, kind: "triage", subject: "\(f.target) · \(f.file)", instructions: instr, prompt: prompt,
                       response: "ERROR: \(error.localizedDescription)", inputTokens: 0, outputTokens: 0, exactTokens: false, seconds: Date().timeIntervalSince(t0), ok: false))
            // Fail loud: an unjudged hit is treated as suspicious.
            return Verdict(level: .malicious, reason: "AI triage failed (\(error.localizedDescription)); treated as suspicious.", action: "Inspect manually; do not run it.", byAI: false)
        }
    }

    func summary(findings: [Finding], coverage: String, log: @Sendable (AICall) -> Void) async -> String {
        let bad = findings.filter { $0.level == .malicious }
        let lines = bad.prefix(25).map { "- [\($0.source.rawValue)] \($0.target) :: \($0.file) — \($0.verdict?.reason ?? "")" }.joined(separator: "\n")
        let instr = AIDefaults.summaryInstructions
        let prompt = """
        Scan coverage: \(coverage)
        Total raw hits: \(findings.count). Confirmed suspicious: \(bad.count). Needing review: \(findings.filter { $0.level == .review }.count).
        \(bad.isEmpty ? "Nothing suspicious was found." : "Suspicious items:\n\(lines)")
        Write the checkup summary with the 2-3 most important next steps.
        """
        let session = LanguageModelSession(instructions: instr)
        let t0 = Date()
        do {
            let r = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy))
            var (i, o, exact) = estimate(prompt, instr, r.content)
            if #available(macOS 27.0, *) { i = r.usage.input.totalTokenCount; o = r.usage.output.totalTokenCount; exact = true }
            log(AICall(time: t0, kind: "summary", subject: "Scan summary", instructions: instr, prompt: prompt, response: r.content,
                       inputTokens: i, outputTokens: o, exactTokens: exact, seconds: Date().timeIntervalSince(t0), ok: true))
            return r.content
        } catch {
            log(AICall(time: t0, kind: "summary", subject: "Scan summary", instructions: instr, prompt: prompt, response: "ERROR: \(error.localizedDescription)",
                       inputTokens: 0, outputTokens: 0, exactTokens: false, seconds: Date().timeIntervalSince(t0), ok: false))
            return "Summary unavailable (\(error.localizedDescription)). \(bad.count) suspicious of \(findings.count) hits."
        }
    }

    /// Fallback when the framework cannot report usage (macOS < 27): ~4 characters per token.
    private func estimate(_ prompt: String, _ instr: String, _ out: String) -> (Int, Int, Bool) {
        ((prompt.count + instr.count) / 4, out.count / 4, false)
    }
}
