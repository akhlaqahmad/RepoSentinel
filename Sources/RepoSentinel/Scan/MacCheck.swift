import Foundation

/// Persistence and process checks for this Mac.
enum MacCheck {
    static func run(_ ctx: Ctx) async throws {
        let home = NSHomeDirectory(), fm = FileManager.default
        let total = 6; var step = 0
        func next(_ s: String) async throws { try await ctx.checkpoint(); step += 1; ctx.progress(step, total, s); ctx.log(.info, s) }
        func add(_ t: String, _ f: String, _ ex: String, _ r: String) {
            ctx.log(.hit, "\(r): \(t)"); ctx.found(Finding(source: .mac, target: t, file: f, excerpt: String(ex.prefix(500)), rule: r))
        }

        try await next("Checking crontab")
        let cron = await runAsync("/usr/bin/crontab", ["-l"])
        if cron.status == 0, !cron.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { add("crontab", "crontab -l", cron.out, "cron entries present") }
        else { ctx.log(.debug, "No crontab") }

        try await next("Inspecting LaunchAgents and LaunchDaemons")
        let sus = try! NSRegularExpression(pattern: #"node |curl |wget|osascript|base64|/tmp/|bash -c|sh -c|python.* -c|eval"#)
        for dir in ["\(home)/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            let items = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".plist") }
            ctx.log(.debug, "\(dir): \(items.count) plists")
            for f in items {
                let path = "\(dir)/\(f)"
                guard let d = NSDictionary(contentsOfFile: path) else { continue }
                let args = ((d["ProgramArguments"] as? [String]) ?? [d["Program"] as? String ?? ""]).joined(separator: " ")
                if !f.hasPrefix("com.apple."), IOC.matches(sus, args) { add(path, f, args, "launch item runs scripting/network tool") }
            }
        }

        try await next("Reading shell startup files")
        for rc in [".zshrc", ".zprofile", ".zshenv", ".bashrc", ".bash_profile", ".profile"] {
            guard let t = try? String(contentsOfFile: "\(home)/\(rc)", encoding: .utf8) else { continue }
            ctx.log(.debug, "~/\(rc) (\(t.count) chars)")
            for l in t.split(separator: "\n") where l.range(of: #"curl[^|]*\|\s*(ba)?sh|base64\s+-d|eval\s*\$\(curl|node\s+\S*api\.js|global\['!'\]"#, options: .regularExpression) != nil {
                add("~/\(rc)", rc, String(l), "suspicious shell startup line")
            }
        }

        try await next("Scanning running processes")
        let ps = await runAsync("/bin/ps", ["-axo", "pid,command"]).out
        for l in ps.split(separator: "\n") where l.range(of: #"node\s+(\./)?(api|init)(\.js)?(\s|$)|fa-solid-\d+|eslint-check\.sh|temp_(auto|interactive)_push"#, options: .regularExpression) != nil {
            add("process", "ps", String(l), "process matches PolinRider pattern")
        }

        try await next("Checking VS Code / Cursor auto-run settings")
        for f in ["Library/Application Support/Code/User/settings.json", "Library/Application Support/Cursor/User/settings.json"] {
            if let t = try? String(contentsOfFile: "\(home)/\(f)", encoding: .utf8), t.contains("folderOpen") { add("~/\(f)", f, "folderOpen in user settings", "auto-run on folder open") }
        }

        try await next("Auditing global git configuration")
        let cfg = await runAsync("/usr/bin/git", ["config", "--global", "--list"]).out
        for l in cfg.split(separator: "\n") {
            let s = String(l).lowercased()
            if s.hasPrefix("core.hookspath=") || s.hasPrefix("include.path=") || (s.hasPrefix("credential.helper=") && !s.contains("osxkeychain") && !s.contains("gh auth") && !s.contains("manager"))
                || (s.hasPrefix("alias.") && s.contains("=!") && s.contains("curl")) {
                add("~/.gitconfig", ".gitconfig", String(l), "git global config")
            }
        }
        ctx.log(.info, "Mac checks complete")
    }
}
