# Offline Capture Implementation Plan

> For agentic workers: use subagent-driven-development for the independent Music Sync task and review; execute the closely coupled iOS steps in this session.

**Goal:** Ship offline music capture with pending recognition on next use and reliable Music Sync delivery.
**Architecture:** Native iOS ShazamKit and SwiftData queue. Matched metadata uses background URLSession delivery. Music Sync exposes a scoped consumer API.
**Tech Stack:** SwiftUI, SwiftData, ShazamKit, App Intents, XCTest, Cherri; existing Python/FastAPI Music Sync service.
**Spec:** ../specs/2026-09-12-offline-capture-design.md

## Global Constraints

- iOS 17+, native Apple frameworks; no substitute recognition provider or Mac dependency.
- Capture starts promptly; pending work runs on each use; no separate manual sync.
- Persist before success; preserve work after interruptions; validate body-level delivery acknowledgement.
- Client configuration consists of service URL and app-issued credential in Keychain; no provider/admin credentials.
- No personal values or credentials in code, fixtures or logs.
- Tests first for behavior, verify failing assertions and perform a real mutation check.
- Do not deploy Music Sync without approval of its concrete tested commit.

### Task 1: Music Sync consumer capture access

**Repository:** ../music-sync
**Files:** app.py; src/core/capture_clients.py; src/core/capture.py if needed for delivery correctness; tests/test_capture_clients.py; tests/test_app.py; AGENTS.md; README.md.
**Interface produced:** HTTPS POST consumer capture endpoint, Authorization: Bearer <app-issued token>, JSON capture_id (UUID), title, artist, apple_music_id, shazam_url. Success JSON includes ok:true, capture_id and isrc. Failure returns non-success without a false acknowledgement. Operator endpoint protected by existing proxy auth issues/revokes capture-only tokens. Keep the old proxy-auth capture route compatible.

- [ ] Read existing capture/archive/API tests and record git base.
- [ ] Write failing tests for missing/invalid/revoked credential, valid capture, malformed UUID/body, replay of successful capture, id reused with changed payload, persistence failure and safe error response. Keep external storage/Spotify mocked only at their I/O boundary.
- [ ] Implement a small capture credential module: independently random tokens, hashed storage in Music Sync-owned operational storage, independent revocation, no token logs. The supported operator API issues credentials; clients never mint provider tokens.
- [ ] Route authorized captures through the existing serialized worker. Persist success receipts keyed by client/capture UUID; verify payload identity on replay. Never acknowledge before capture success and receipt persistence. Resolve concrete capture defects encountered that affect safe replay or wrong-version delivery, with failing regressions first.
- [ ] Run focused tests, one mutation check, full non-integration pytest and ruff. Update API and ownership documentation. Commit every safe repo change with no agent attribution. Do not push or deploy. Report exact endpoint/response/enrollment contract and evidence.

### Task 2: Durable iOS queue and ShazamKit import

**Files:** App/CaptureStore.swift, App/Recognition.swift, App/CaptureIntent.swift; Tests/CaptureTests.swift.
**Interface:** CaptureStore saves signatures and state; recognition accepts persisted SHSignature bytes; the capture intent receives IntentFile and awaits bounded processing.

- [ ] Scaffold the iOS template with portable signing configuration and no unused dependencies.
- [ ] Write failing tests using a temporary persistent SwiftData store: import then reopen retains signatures; failed recognition remains pending; matches retain metadata; repeated use resumes without losing current capture. Test body-level upload acknowledgement independently.
- [ ] Implement atomic signature files, SwiftData metadata and bounded next-use draining with current capture priority. Preserve all failures and save progress after each item.
- [ ] Generate a real signature from synthetic PCM in tests, serialize and deserialize it. Add the native ShazamKit adapter and App Intent with cancellation/timeout handling.
- [ ] Run simulator unit tests and compile checks. Mutate success/failure handling and confirm regression detection.

### Task 3: Delivery, native capture UI and Shortcut

**Files:** App/Delivery.swift, App/Configuration.swift, App/ContentView.swift, App/App.swift, Shortcuts/Capture.cherri; Tests/DeliveryTests.swift and UI tests.
**Consumes:** Task 1 consumer capture contract and Task 2 queue state.

- [ ] Write failing response/retry/configuration tests and a UI smoke test for capture availability and configuration validation.
- [ ] Implement file-backed background upload, stable task identifiers, bounded response collection, persisted acknowledgement and automatic recovery on app/intent use. Store token in Keychain and URL in app preferences; reject insecure endpoints.
- [ ] Add prompt native recording, queue status and minimal settings. Compile the record-audio Shortcut using the native import intent; inspect generated actions.
- [ ] Run simulator checks, UI smoke and review. Provision signing through supported Apple tools and build/install a debug phone app. Prove saved signature recognition on device and request only the physical microphone/airplane-mode verification that cannot be performed programmatically.

### Task 4: Review, publication and completion

- [ ] Review the app and Music Sync changes against the spec and correct important findings.
- [ ] Update README, current AGENTS, Notion design/build task and project catalog. Create the GitHub repo only after visibility choice; add description/topics.
- [ ] Commit and push non-deploying code. Request approval for Music Sync deployment after its tested commit is reviewable, then watch CI and verify the service.
- [ ] Enroll the phone via the supported app API and secure storage, verify end-to-end delivery and close the build task only when implementation and required validation are complete.
