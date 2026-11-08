import Testing
import Foundation
@testable import RepoSentinel

@Suite struct IOCTests {
    @Test func flagsPaddedPayload() {
        let src = "module.exports={};" + String(repeating: " ", count: 150) + "global['!']='8-1'"
        #expect(IOC.inspect(path: "postcss.config.js", text: src)?.rule == "payload marker")
    }
    @Test func flagsNodeApiScript() {
        #expect(IOC.inspect(path: "package.json", text: #"{"scripts":{"dev":"node api.js && next dev"}}"#) != nil)
    }
    @Test func ignoresNormalConfig() {
        #expect(IOC.inspect(path: "package.json", text: #"{"scripts":{"dev":"next dev"}}"#) == nil)
    }
    @Test func fontDropperPathMatches() {
        #expect(IOC.matches(IOC.font, "public/fonts/fa-solid-700.otf"))
        #expect(!IOC.matches(IOC.font, "public/fonts/Inter-700.otf"))
    }
    @Test func gateReleasesWaitersOnResume() async {
        let g = Gate(); await g.pause()
        async let w: Void = g.wait()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await g.resume(); await w
    }
    @Test func remoteFindingBuildsGitHubURL() {
        var f = Finding(source: .remote, target: "me/repo", file: "a/b.js", excerpt: "", rule: "x"); f.branches = ["feat/x"]
        #expect(f.url?.absoluteString == "https://github.com/me/repo/blob/feat/x/a/b.js")
    }
    @Test func localScanFindsPlantedPayload() async throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("rs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try ("x=1;" + String(repeating: " ", count: 200) + "eval(1)").write(to: d.appendingPathComponent("vite.config.js"), atomically: true, encoding: .utf8)
        let box = Counter()
        let ctx = Ctx(log: { _, _ in }, found: { _ in box.inc() }, progress: { _, _, _ in }, active: { _, _ in }, checkpoint: {})
        _ = try await LocalScan.scan(repo: d, ctx)
        #expect(box.value == 1)
        try? FileManager.default.removeItem(at: d)
    }
    @Test func strongFingerprintsCannotBeDowngraded() {
        func f(_ ex: String, _ rule: String = "payload marker") -> Finding { Finding(source: .local, target: "t", file: "x.js", excerpt: ex, rule: rule) }
        #expect(IOC.isStrong(f("global['!']='8-1'")))
        #expect(IOC.isStrong(f("fetch('https://api.trongrid.io/x')")))
        #expect(IOC.isStrong(f("", "font dropper")))
        #expect(!IOC.isStrong(f("\"runOptions\": {\"runOn\": \"folderOpen\"}")))
    }
}
