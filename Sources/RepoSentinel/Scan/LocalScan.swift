import Foundation

enum LocalScan {
    static func discover(_ ctx: Ctx) async throws -> [URL] {
        var repos = Set<URL>()
        let fm = FileManager.default
        var visited = 0
        for root in ctx.roots {
            ctx.log(.info, "Looking for git repositories under \(root.path)")
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]) else {
                ctx.log(.warn, "Cannot read \(root.path) (no permission?)"); continue
            }
            while let u = en.nextObject() as? URL {
                visited += 1
                if visited % 400 == 0 { try await ctx.checkpoint(); ctx.progress(0, 0, "Looking in \(u.deletingLastPathComponent().lastPathComponent)… (\(repos.count) repos found)") }
                let n = u.lastPathComponent
                if n == ".git" {
                    let repo = u.deletingLastPathComponent()
                    if repos.insert(repo).inserted { ctx.log(.debug, "Found repo \(repo.path)") }
                    en.skipDescendants(); continue
                }
                if ctx.skipDirs.contains(n) || en.level > 7 { en.skipDescendants() }
            }
        }
        ctx.log(.info, "Found \(repos.count) git repositories")
        return repos.sorted { $0.path < $1.path }
    }

    static func scan(repo: URL, _ ctx: Ctx) async throws -> Int {
        let fm = FileManager.default
        var files = 0, hits = 0
        func hit(_ rel: String, _ ex: String, _ rule: String) {
            hits += 1
            let f = Finding(source: .local, target: repo.path, file: rel, excerpt: ex, rule: rule)
            ctx.log(.hit, "\(repo.lastPathComponent): \(rel) — \(rule)"); ctx.found(f)
        }
        // git hooks are a common persistence trick
        let hooks = repo.appendingPathComponent(".git/hooks")
        for h in (try? fm.contentsOfDirectory(atPath: hooks.path)) ?? [] where !h.hasSuffix(".sample") {
            let p = hooks.appendingPathComponent(h)
            if let t = try? String(contentsOf: p, encoding: .utf8) { hit(".git/hooks/\(h)", String(t.prefix(500)), "git hook") }
        }
        guard let en = fm.enumerator(at: repo, includingPropertiesForKeys: nil) else { return 0 }
        while let u = en.nextObject() as? URL {
            let n = u.lastPathComponent
            if ctx.skipDirs.contains(n) { en.skipDescendants(); continue }
            files += 1
            if files % 500 == 0 { try await ctx.checkpoint() }
            let rel = String(u.path.dropFirst(repo.path.count + 1))
            if n.hasSuffix(".bat"), n.lowercased().contains("push") { hit(rel, "", "push-tool dropper (.bat)") }
            if IOC.matches(IOC.font, rel) { hit(rel, "fa-solid font file (known JS dropper disguise)", "font dropper"); continue }
            if n == ".gitignore" {
                if let t = try? String(contentsOf: u, encoding: .utf8), IOC.matches(IOC.gitignore, t) {
                    hit(rel, "leftover ignore lines for temp_*push.bat / branch_structure.json", "gitignore IOC (harmless leftover)")
                }
                continue
            }
            guard IOC.matches(IOC.cfg, rel), let t = try? String(contentsOf: u, encoding: .utf8) else { continue }
            if let (rule, ex) = IOC.inspect(path: rel, text: t) { hit(rel, ex, rule) }
        }
        ctx.log(.debug, "\(repo.lastPathComponent): \(files) files checked, \(hits) hits")
        return files
    }
}
