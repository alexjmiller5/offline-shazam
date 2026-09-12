# Offline Shazam

Native SwiftUI app for iOS 17+. Uses Apple ShazamKit to identify music while listening and persist offline signatures for automatic recognition on subsequent use. No third-party recognition service or Mac runtime dependency.

## Source and checks

`project.yml` is canonical; `.xcodeproj` and Info.plist are generated. Sources live in `App/`, unit/integration tests in `Tests/`, UI tests in `UITests/`. `just gen` resolves the XcodeGen executable's real path because Nix profile symlinks otherwise hide its bundled settings. Build output belongs outside a synced source checkout to avoid resource-fork signing failures.

Run `just test` for real ShazamKit custom-catalog matching, durable queue behavior, Keychain, URLSession, and UI coverage. Simulator tests use local ad hoc signing so Keychain access has an application identity. `just check` builds without a developer account. Production Shazam catalog access and microphone behavior still need a provisioned phone smoke test.

Device signing and installation use caller-supplied `IOS_TEAM_ID`, `IOS_PROFILE`, and `IOS_DEVICE_ID`. ShazamKit must be enabled as an App ID service in the Apple Developer account; it does not use a `com.apple.developer.shazamkit` entitlement. There is no deployment workflow; `just deploy` is the explicit local Ad Hoc build/install interface. Native account sign-in and microphone permission remain user state.

## Queue invariants

- Start a new capture promptly; backlog work must not delay recording.
- Feed microphone audio to native ShazamKit streaming recognition while generating the offline signature from the same audio. Stop early on a match; retain useful audio if recognition fails or connectivity drops.
- Persist the signature file and SwiftData record before saying saved.
- Await recognition within the app or App Intent lifetime. Never start detached recognition and return from an intent.
- Bound a recognition pass to three captures and a six-second timeout each. Prioritize the current capture, then previously unattempted work.
- Persist a match before enqueueing a file-backed background URLSession upload. Reuse matched metadata on delivery retries.
- Display and enqueue each match before slower backlog recognition. Current online identification and upload must not wait for a future invocation.
- Mark delivered only after a valid response confirms the same capture UUID and recording. Retain all unfinished work through network, auth, and malformed-response failures.
- Show missing connection, active upload, scheduled retry, and confirmed delivery separately. Saving a connection enqueues matched captures immediately. Retry persisted deadlines with one timer while the app can run, honoring Retry-After and a 30-second minimum; authentication failures pause until Settings repairs the connection.
- Reattach the background URLSession on OS relaunch and finish the OS callback after persistence.

## Ownership and configuration

Offline Shazam owns its app, local queue, signatures, and device Keychain connection. Music Sync is an intentional shared service through its capture-only HTTP API. It owns Spotify access, client issuance/revocation, and delivery receipts. The app never shares Music Sync's backing storage or provider tokens. Removing this app or revoking its token does not affect other callers. Removing the Music Sync service prevents delivery and leaves the phone's queue intact.

Client enrollment asks only for an HTTPS capture URL and an app-issued bearer token, saved in Keychain. No credentials or personal configuration belong in source, Info.plist, defaults, fixture data, or logs. No app runtime secrets or CI service account are needed in this repository. There is no analytics dependency.
