# AGENTS.md — RepoSentinel

Guidance for AI coding agents (Claude Code, Codex, Cursor, Copilot…) working in this repo. Humans: see [README.md](README.md).

## What this is
SwiftUI macOS app (SwiftPM, no Xcode project) that scans for the PolinRider worm and uses Apple `FoundationModels` on-device to triage hits.

## Commands
| Task | Command |
|---|---|
| Build | `swift build -c release` |
| Test | `swift test` (must stay green) |
| Package | `./scripts/build.sh` → `dist/RepoSentinel.app` + `.dmg` |
| AI smoke test | `.build/out/Products/Release/RepoSentinel --selftest` |
| Engine e2e | `RS_NO_PERSIST=1 .build/out/Products/Release/RepoSentinel --selftest-engine` |

Swift language mode is **v5** (set in `Package.swift`); toolchain is Swift 6.x / Xcode 27.

## Xcode project
`RepoSentinel.xcodeproj` is generated from `project.yml` (`xcodegen`) and shares `Sources/` and `Tests/` with `Package.swift`. After adding/removing files or changing settings, edit `project.yml` and run `xcodegen`; commit both. Build check: `xcodebuild -project RepoSentinel.xcodeproj -scheme RepoSentinel -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`.

## Layout
```
Sources/RepoSentinel/
  Core/    Models (Finding, Verdict, Stage…), IOC (regexes + remediation), Process (async runner)
  Scan/    Ctx (scanner↔engine contract), LocalScan, GitHubScan, MacCheck
  AI/      AIService (FoundationModels triage + summary, call log, token usage)
  Engine/  ScanEngine (state machine, pause/stop), Prefs (defaults, JSON Store, Gate), Report
  UI/      App + one file per screen
```

## Invariants — do not break
1. **Read-only.** Never write to, delete from, or upload user files/repos. No `Process` that mutates anything.
2. **Strong IOCs beat the AI.** `IOC.isStrong` findings must stay `.malicious`; the model may explain, never clear them. Unjudged or AI-failed hits default to **malicious** (fail loud).
3. **Cancellation is cooperative.** Long loops must `try await ctx.checkpoint()` — that is the single place pause and stop take effect. Subprocesses go through `runAsync` so cancelling terminates them.
4. **Never execute scanned content.** Excerpts are displayed as text only.
5. **No hardcoded secrets;** GitHub access is only via the user's `gh` session.
6. UI state lives in `ScanEngine` (`@MainActor`); scanners report through `Ctx` closures, never touching UI types.

## Adding a detection
Add the regex to `IOC` → handle it in the right scanner → add a case to `IOC.remediation(for:)` → add a test in `Tests/RepoSentinelTests/IOCTests.swift`. If it is unambiguous, include it in `IOC.strong`.

## Gotchas
- `FoundationModels` exact token usage needs macOS 27 (`#available`); older OSes fall back to a ~4 chars/token estimate.
- Don't enumerate with `for … in FileManager.enumerator` in async code; use `while let … = en.nextObject()`.
- `RS_NO_PERSIST=1` stops tests from writing `~/Library/Application Support/RepoSentinel`.
