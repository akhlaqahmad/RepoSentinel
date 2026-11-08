# Architecture

```
            ┌────────────── SwiftUI views (UI/) ──────────────┐
            │ Overview · Findings · Activity · AI · History   │
            └───────────────▲─────────────────────────────────┘
                            │ @Published state
                  ┌─────────┴─────────┐        pause/stop
                  │  ScanEngine (MainActor)  ◄── Gate (actor) + Task cancellation
                  └──┬────────┬────────┬────────┬──┘
        Ctx closures │        │        │        │ await
              ┌──────┴──┐ ┌───┴────┐ ┌─┴──────┐ ┌┴────────────┐
              │MacCheck │ │LocalScan│ │GitHub  │ │ AIService   │
              │         │ │         │ │Scan    │ │FoundationMod│
              └─────────┘ └─────────┘ └───┬────┘ └─────────────┘
                                          └── `gh api` via runAsync
```

## Run lifecycle
`idle → running ⇄ paused → finished | stopped`, plus `stopping` while cancellation drains.
Stages run in order: **Mac → Local → GitHub → AI triage → Summary**. Each scanner gets a stage-bound `Ctx` with `log`, `found`, `progress`, `active` and `checkpoint`.

## Pause / stop
`checkpoint()` = `checkCancellation` → `await gate.wait()` → `checkCancellation`. Pause closes the `Gate`; every scanner parks at its next checkpoint. Stop cancels the root `Task` and opens the gate. `runAsync` installs a cancellation handler that terminates in-flight `gh`/`git` processes.

## Verdicts
1. Scanners emit `Finding`s (rule + excerpt). Some (SSH keys) arrive pre-judged as *review*.
2. Distinct `(rule, excerpt)` pairs are triaged once by the on-device model (`@Generable AIVerdict`, greedy sampling) and applied to duplicates.
3. `IOC.isStrong` findings are forced `.malicious` regardless of the model. A failed AI call also yields `.malicious`.
4. Every call is recorded as an `AICall` (instructions, prompt, response, exact tokens, seconds) for the AI Insights page.

## Persistence
`~/Library/Application Support/RepoSentinel/` — `history.json` (last 30 scans), `ignored.json`. Preferences in `UserDefaults` (`Pref` keys).
