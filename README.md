<div align="center">

# 🛡️ RepoSentinel

**A native macOS malware checkup for your Mac, your local git repos, and your GitHub account —
triaged by Apple's on-device AI. Nothing leaves your machine.**

![platform](https://img.shields.io/badge/macOS-26%2B-blue) ![swift](https://img.shields.io/badge/Swift-6.x-orange) ![ai](https://img.shields.io/badge/AI-Apple%20Foundation%20Models-black) ![license](https://img.shields.io/badge/license-MIT-green)

</div>

RepoSentinel hunts for the **PolinRider / EtherHiding** supply-chain worm: obfuscated JavaScript hidden in `*.config.js`,
`package.json` scripts, `.vscode/tasks.json`, fake `fa-solid-*` font files and `build.gradle`, force-pushed into repos with
stolen credentials. It scans, explains every hit in plain English using the **on-device Apple Foundation Models**, and tells you what to do.

## Why it's different
- **100% on-device AI.** Triage and summaries run on the Mac's Neural Engine through `FoundationModels`. No API keys, no per-call cost, no code uploaded.
- **The AI can't be talked out of a real hit.** Strong worm fingerprints are decided by rules; the model only explains them and may only *downgrade* weak signals.
- **Transparent.** Every system prompt, prompt, response, exact token count and latency is on the *AI Insights* page, next to your cost ($0.00) and an illustrative cloud-equivalent.
- **Read-only.** It never modifies, deletes or uploads your files or repos. Matched content is shown as text, never executed.

## What it checks
| Area | Checks |
|---|---|
| **This Mac** | cron, LaunchAgents/Daemons, shell startup files, running processes, VS Code/Cursor `folderOpen` auto-run, global git config |
| **Local repos** | payload markers in config/`package.json`/gradle, fake font droppers, `.bat` push droppers, planted git hooks, leftover `.gitignore` IOCs |
| **GitHub** | every pushable repo × **every branch** via your `gh` login, plus an audit of SSH keys on your account |

## Features
- Live **Activity** log (verbose → hits only), per-stage progress, parallel work list, elapsed time and ETA
- **Pause / Resume / Stop / Restart** (⌘R · ⌥⌘P · ⌘. · ⇧⌘R)
- Findings triage: *Suspicious / Review / Benign / Ignored*, "NEW since last scan", reveal in Finder, open on GitHub, ignore list
- History of the last 30 scans with new/resolved diff · Markdown & JSON export · completion notification

## Install
Requires **macOS 26+, Apple silicon, Apple Intelligence enabled** (without it, the app falls back to rule-based verdicts) and, for the GitHub scan, `brew install gh && gh auth login`.

```bash
git clone https://github.com/akhlaqahmad/RepoSentinel.git && cd RepoSentinel
./scripts/build.sh          # tests → release build → icon → signed .app + .dmg in dist/
open dist/RepoSentinel.app
```
First launch of an ad-hoc-signed build: right-click → **Open**. For distribution, sign with a Developer ID and notarize — see [docs/RELEASING.md](docs/RELEASING.md).

## Develop
Open **`RepoSentinel.xcodeproj`** in Xcode (⌘R to run, ⌘U to test), or use SwiftPM:
```bash
swift build            # debug build
swift test             # unit tests (Swift Testing)
RepoSentinel --selftest          # on-device model smoke test (prints exact token counts)
RS_NO_PERSIST=1 RepoSentinel --selftest-engine   # end-to-end: scan, pause, resume, stop, restart
```
Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Contributors and AI coding agents: read [AGENTS.md](AGENTS.md) first.

## Privacy & safety
No telemetry. No network calls except read-only GitHub API requests made through your own `gh` session. The app is not sandboxed
(it must read arbitrary repos and run `gh`), so it is distributed outside the Mac App Store. See [SECURITY.md](SECURITY.md).

## License
[MIT](LICENSE)
