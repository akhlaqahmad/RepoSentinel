# Releasing

1. `swift test` and `RS_NO_PERSIST=1 … --selftest-engine` must pass.
2. One-time: create a **Developer ID Application** certificate and store notary credentials:
   `xcrun notarytool store-credentials my-profile --apple-id <you> --team-id <TEAMID>`
3. `VERSION=1.1.0 SIGN_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=my-profile ./scripts/build.sh`
4. Upload `dist/RepoSentinel-<version>.dmg` to a GitHub Release.

Without `SIGN_ID` the script ad-hoc signs (fine locally; other Macs need right-click → Open).
