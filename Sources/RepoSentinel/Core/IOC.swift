import Foundation

/// Indicators of compromise for the PolinRider / EtherHiding worm.
enum IOC {
    static let cfg = try! NSRegularExpression(pattern: #"(^|/)(postcss|tailwind|next|babel|vite|eslint|nuxt|webpack|svelte|astro|jest|metro)\.config\.(js|mjs|cjs|ts)$|(^|/)\.eslintrc\.(js|cjs)$|^[^/]+\.(js|mjs|cjs)$|(^|/)package\.json$|(^|/)build\.gradle(\.kts)?$|(^|/)\.vscode/tasks\.json$|(^|/)\.vscode/eslint-check\.sh$"#)
    static let font = try! NSRegularExpression(pattern: #"(^|/)fa-solid-\d+\.(woff2?|eot|ttf|otf)$"#)
    static let marker = try! NSRegularExpression(pattern: #"global\['!'\]|global\.i ?= ?['"]A1\d-|node (api|init)(\.js)? &&|node \./public/fonts|[ \t]{100,}\S|_\$_[0-9a-f]{4}\[|blastapi\.io|trongrid\.io|bsc-dataseed|bsc-rpc\.publicnode|folderOpen"#)
    /// Unambiguous worm fingerprints. A hit on these is never downgraded by the AI.
    static let strong = try! NSRegularExpression(pattern: #"global\['!'\]|global\.i ?= ?['"]A1\d-|_\$_[0-9a-f]{4}\[|blastapi\.io|trongrid\.io|bsc-dataseed|bsc-rpc\.publicnode|node (api|init)(\.js)? &&|node \./public/fonts"#)
    static func isStrong(_ f: Finding) -> Bool { f.rule == "font dropper" || f.rule == "push-tool dropper (.bat)" || matches(strong, f.excerpt) }
    static let gitignore = try! NSRegularExpression(pattern: #"temp_auto_push\.bat|temp_interactive_push\.bat|branch_structure\.json"#)
    static let defaultSkip: Set<String> = ["node_modules", ".git", ".next", "dist", "build", "Pods", ".venv", "venv", ".expo", "DerivedData", ".dart_tool", "vendor", "Library", ".Trash", "Movies", "Music", "Pictures", ".cache", ".npm", ".gradle", ".cargo", ".rustup", ".pyenv"]

    static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Returns (rule, excerpt) if the file content looks like a payload.
    static func inspect(path rel: String, text: String) -> (rule: String, excerpt: String)? {
        let ns = text as NSString
        if let m = marker.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let lo = max(0, m.range.location - 80), hi = min(ns.length, m.range.location + m.range.length + 200)
            let ex = ns.substring(with: NSRange(location: lo, length: hi - lo))
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return ("payload marker", ex)
        }
        if !rel.hasSuffix(".json"), let l = text.split(separator: "\n", omittingEmptySubsequences: false).first(where: { $0.count > 500 }) {
            return ("very long line (>500 chars)", String(l.prefix(300)))
        }
        return nil
    }

    /// What the user should do about a given rule.
    static func remediation(for rule: String) -> String {
        switch rule {
        case "payload marker", "very long line (>500 chars)":
            return "Do not run npm/dev/build in this tree. Restore the file from the last genuine commit (git show <good-sha>:<path>), commit the fix forward, then rotate any secrets that were on this machine."
        case "font dropper": return "Delete the fake fa-solid font file and any task or script that executes it (.vscode/tasks.json, package.json scripts)."
        case "push-tool dropper (.bat)": return "Delete the .bat file and remove its name from .gitignore. Check git history for forged commits."
        case let r where r.hasPrefix("gitignore"): return "Harmless leftover. Optionally delete the temp_*push.bat / branch_structure.json lines from .gitignore."
        case "git hook": return "Open the hook. If you did not write it (and it is not from husky/lefthook), delete it."
        case "launch item runs scripting/network tool": return "Open the plist and confirm you installed the program it runs. Unload with `launchctl bootout` and delete if unknown."
        case "suspicious shell startup line": return "Remove the line from the shell startup file if you did not add it."
        case "ssh key": return "Open github.com/settings/keys and remove any key you do not recognise."
        default: return "Inspect manually before running anything from this location."
        }
    }
}
