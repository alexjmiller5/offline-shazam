# Offline Shazam

Identify music on an iPhone as you listen with Apple's ShazamKit. Offline captures are saved automatically and identified on your next online use. Music Sync delivers recognized songs to Spotify.

## Use

1. Open Settings and enter the Music Sync capture URL and a capture-only access token. The connection is stored in the iOS Keychain.
2. Tap **Capture song**, or use the **Capture song** App Shortcut. Shazam listens and stops recording as soon as it identifies the song. If there is no early match, the app saves up to 15 seconds as a Shazam signature for identification.
3. Check recent captures for their status: saved, identified, added to Spotify, or not identified. There is no manual sync step.

The capture Shortcut opens the app to use the microphone. For an existing audio-recording Shortcut, add the **Save audio capture** action after **Record Audio**, passing its audio output. Clips must be at most 30 seconds and 16 MiB. This action waits for signature persistence and a bounded recognition pass before returning; it does not launch detached recognition work.

Live recognition receives the same microphone audio used to generate the offline signature. Captures and recognized metadata are stored before reporting success. A new match is displayed and queued for Spotify delivery before older recognition work. Saved-signature recognition processes at most three captures per invocation, with the new capture first, and queues each match for delivery as it is found. A larger backlog continues on subsequent use. Delivery uses file-backed background URLSession uploads, following the same native iOS mechanism used by Receptor. iOS may continue an enrolled upload while the app is suspended. Recognition of an offline signature needs the app to run again; reconnecting while it stays closed does not guarantee immediate recognition. Force-quitting the app can also cancel background transfers until you open it again.

Shazam provides recognition. No Mac or replacement recognition provider is required. When Shazam supplies an ISRC, Music Sync requires that exact recording on Spotify. Otherwise, it uses conservative title and artist matching. A missing Spotify match remains pending rather than adding a different recording.

## Develop and install

Requirements: macOS, Xcode, XcodeGen, just, and an iOS 17+ phone or simulator. Install development tools through your machine's supported package configuration. No third-party Swift packages are required.

```sh
just dev       # Generate the Xcode project and open it
just test      # Unit, native SDK, Keychain, delivery, and UI tests
just check     # Simulator build
IOS_TEAM_ID='<developer-team>' just build
IOS_TEAM_ID='<developer-team>' IOS_PROFILE='<ad-hoc-profile>' IOS_DEVICE_ID='<device-id>' just deploy
```

`project.yml` is the source of truth for the generated Xcode project. Override `IOS_TEST_DESTINATION` to select an installed simulator, and `IOS_DERIVED_DATA` for build output. The default build directory lives in Xcode's DerivedData location, outside the source checkout. Simulator tests use local ad hoc code signing so the real Keychain works; they require no developer account or provisioning profile.

For a device build, sign into your Apple Developer account in Xcode Settings. Set the app's bundle identifier in `project.yml` if building under another publisher. Register that explicit identifier and enable **ShazamKit** under **App Services** in the [Apple Developer account](https://developer.apple.com/help/account/services/shazamkit). ShazamKit is an App ID service, not a code-signing entitlement: do not add a `com.apple.developer.shazamkit` entitlement. For a stable installation, supply an Apple Distribution identity and an Ad Hoc profile for that App ID and phone. The local `deploy` recipe builds and installs the app; this repository has no automatic deployment workflow.

Allow microphone access on the phone when prompted. On a replacement phone, reinstall and issue a new capture-only Music Sync token, then enter it in Settings. Revoke the old device's token through Music Sync. The Keychain credential is device-bound. Local pending captures are not a cross-device sync service.

## Service contract

Music Sync owns the capture API, Spotify account connection, revocable client tokens, and durable delivery receipts. Offline Shazam knows only its HTTPS capture endpoint and its own issued bearer token. It carries no Spotify, Modal, R2, or infrastructure credentials.

A request contains `capture_id` (stable UUID), `title`, `artist`, `apple_music_id`, and `shazam_url`, with optional `isrc`. Success requires a 2xx response with `ok: true`, the same capture UUID, and a nonempty recording ISRC. If Shazam supplied an ISRC, the receipt must agree. Other responses retain the matched metadata for retry; numeric or HTTP-date `Retry-After` is respected. Request redirects are rejected. The server durably pins the selected recording before Spotify side effects and deduplicates repeat requests.

Signatures and queue metadata stay in the app's Application Support directory. Live microphone audio is processed in memory; temporary import files are removed after processing. Successful delivery removes the signature while retaining recent song history. Unidentified recordings remain visible and retained. There is no analytics SDK.

The waveform icon is [Tabler wave-sine](https://icon-sets.iconify.design/tabler/wave-sine/), used under the MIT license.
