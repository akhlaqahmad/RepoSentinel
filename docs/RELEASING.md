# Releasing

1. `swift test` and `RS_NO_PERSIST=1 … --selftest-engine` must pass.
2. One-time: create a **Developer ID Application** certificate and store notary credentials:
   `xcrun notarytool store-credentials my-profile --apple-id <you> --team-id <TEAMID>`
3. `VERSION=1.1.0 SIGN_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=my-profile ./scripts/build.sh`
4. Upload `dist/RepoSentinel-<version>.dmg` to a GitHub Release.

Without `SIGN_ID` the script ad-hoc signs (fine locally; other Macs need right-click → Open).

## Signing from Xcode (get a Developer ID certificate)
This is a Swift package, so signing happens in `scripts/build.sh`, but the certificate comes from Xcode:
1. Xcode → Settings → **Accounts** → sign in with your Apple ID (must be in the paid Apple Developer Program).
2. Select your team → **Manage Certificates…** → **+** → **Developer ID Application**. (Needs the Account Holder or Admin role.)
3. Check it: `security find-identity -v -p codesigning | grep "Developer ID Application"`. `build.sh` picks it up automatically.
4. Create an app-specific password at appleid.apple.com, then
   `xcrun notarytool store-credentials my-profile --apple-id <you> --team-id <TEAMID>`.
5. `NOTARY_PROFILE=my-profile ./scripts/build.sh` → signed, notarized, stapled DMG in `dist/`.

Signing identity order used by the script: `$SIGN_ID` → Developer ID Application → Apple Development (this Mac only) → ad-hoc.

## Releasing from Xcode instead
Open `RepoSentinel.xcodeproj` → Signing & Capabilities → choose your Team → **Product ▸ Archive** → **Distribute App ▸ Direct Distribution** (Developer ID + notarization handled by Xcode). Export the `.app`, then wrap it in a DMG with `hdiutil` (see the end of `scripts/build.sh`).
