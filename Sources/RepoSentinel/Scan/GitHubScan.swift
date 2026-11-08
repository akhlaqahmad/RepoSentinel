import Foundation

/// Read-only scan of every pushable GitHub repo via the `gh` CLI (all branches).
enum GitHubScan {
    static let calls = Counter()

    static func api(_ path: String) async -> Any? {
        guard let gh = ghPath else { return nil }
        calls.inc()
        let r = await runAsync(gh, ["api", path])
        guard r.status == 0, let d = r.out.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    static func loggedIn() async -> Bool {
        guard let gh = ghPath else { return false }
        return await runAsync(gh, ["auth", "status"]).status == 0
    }

    @discardableResult static func run(_ ctx: Ctx) async throws -> Int {
        guard let gh = ghPath else { ctx.log(.warn, "GitHub CLI (gh) not found — install with `brew install gh`"); throw ScanSkip("gh not installed") }
        guard await loggedIn() else { ctx.log(.warn, "gh is not logged in — run `gh auth login` in Terminal"); throw ScanSkip("gh not logged in") }
        calls.reset()

        if let me = (await api("user") as? [String: Any])?["login"] as? String { ctx.log(.info, "Signed in to GitHub as @\(me)") }
        try await ctx.checkpoint()
        await auditKeys(ctx)

        ctx.progress(0, 0, "Listing repositories…")
        ctx.log(.info, "Listing repositories you can push to (owner, collaborator, org)…")
        let list = await runAsync(gh, ["api", "--paginate", "user/repos?per_page=100&affiliation=owner,collaborator,organization_member",
                                       "--jq", #".[] | select(.permissions.push and (.archived|not)) | "\(.full_name) \(.default_branch)""#])
        guard list.status == 0 else { ctx.log(.error, "Could not list repositories (gh exit \(list.status))"); throw ScanSkip("repo list failed") }
        let repos = list.out.split(separator: "\n").compactMap { l -> (String, String)? in
            let p = l.split(separator: " "); return p.count == 2 ? (String(p[0]), String(p[1])) : nil }
        ctx.log(.info, "Scanning \(repos.count) repositories, all branches (archived repos skipped)")
        let done = Counter()
        try await forEachConcurrent(repos, limit: ctx.concurrency) { (name, def) in
            try await ctx.checkpoint()
            ctx.active(name, true); defer { ctx.active(name, false) }
            try await scan(repo: name, defaultBranch: def, ctx)
            ctx.progress(done.inc(), repos.count, name)
        }
        ctx.log(.info, "GitHub scan used \(calls.value) API calls")
        return repos.count
    }

    static func auditKeys(_ ctx: Ctx) async {
        ctx.log(.info, "Auditing SSH keys on your GitHub account…")
        guard let keys = await api("user/keys") as? [[String: Any]] else { ctx.log(.warn, "Could not read SSH keys (token may lack read:public_key)"); return }
        for k in keys {
            let title = k["title"] as? String ?? "(untitled)", key = (k["key"] as? String ?? "").prefix(48)
            let created = (k["created_at"] as? String) ?? "unknown date"
            var f = Finding(source: .remote, target: "github.com/settings/keys", file: title, excerpt: "added \(created) · \(key)…", rule: "ssh key")
            f.verdict = Verdict(level: .review, reason: "A stolen-credential worm can add its own SSH key. Confirm you recognise this one.", action: "Remove it at github.com/settings/keys if unknown.", byAI: false)
            ctx.found(f)
        }
        ctx.log(.info, "\(keys.count) SSH key(s) listed for review")
    }

    static func scan(repo: String, defaultBranch: String, _ ctx: Ctx) async throws {
        var branches: [String] = []; var page = 1
        while let bs = await api("repos/\(repo)/branches?per_page=100&page=\(page)") as? [[String: Any]] {
            branches += bs.compactMap { $0["name"] as? String }; if bs.count < 100 { break }; page += 1
        }
        if branches.isEmpty { ctx.log(.warn, "\(repo): no branches readable (empty repo or no access)"); return }
        if let i = branches.firstIndex(of: defaultBranch) { branches.swapAt(0, i) }
        ctx.log(.debug, "\(repo): \(branches.count) branches")

        var blobs: [String: (rule: String, excerpt: String)?] = [:]
        var agg: [String: Finding] = [:]
        for b in branches {
            try await ctx.checkpoint()
            guard let br = await api("repos/\(repo)/branches/\(b.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? b)") as? [String: Any],
                  let sha = (br["commit"] as? [String: Any])?["sha"] as? String,
                  let tree = await api("repos/\(repo)/git/trees/\(sha)?recursive=1") as? [String: Any],
                  let entries = tree["tree"] as? [[String: Any]] else {
                ctx.log(.warn, "\(repo)@\(b): tree unreadable — skipped"); continue
            }
            ctx.log(.debug, "\(repo)@\(b): \(entries.count) entries")
            for e in entries {
                guard let p = e["path"] as? String, !p.contains("node_modules/"), let bsha = e["sha"] as? String else { continue }
                var hit: (rule: String, excerpt: String)?
                if IOC.matches(IOC.font, p) { hit = ("font dropper", "fa-solid font file (known JS dropper disguise)") }
                else if e["type"] as? String == "blob", IOC.matches(IOC.cfg, p) {
                    if blobs[bsha] == nil {
                        if let blob = await api("repos/\(repo)/git/blobs/\(bsha)") as? [String: Any], let c = blob["content"] as? String,
                           let d = Data(base64Encoded: c.replacingOccurrences(of: "\n", with: "")) {
                            blobs[bsha] = .some(IOC.inspect(path: p, text: String(decoding: d, as: UTF8.self)))
                        } else { blobs[bsha] = .some(("fetch failed", "could not read file — treated as suspicious")) }
                    }
                    hit = blobs[bsha] ?? nil
                }
                guard let h = hit else { continue }
                let k = p + "|" + h.rule + "|" + h.excerpt
                if agg[k] == nil { agg[k] = Finding(source: .remote, target: repo, file: p, excerpt: h.excerpt, rule: h.rule) }
                agg[k]!.branches.append(b)
            }
        }
        for f in agg.values {
            ctx.log(.hit, "\(repo): \(f.file) — \(f.rule) on \(f.branches.count) branch(es)"); ctx.found(f)
        }
        ctx.log(.debug, "\(repo): done (\(agg.count) hits)")
    }
}

struct ScanSkip: Error { let reason: String; init(_ r: String) { reason = r } }
