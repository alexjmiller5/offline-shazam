# Offline capture design

An iOS 17+ app uses ShazamKit to capture music offline and recognize pending signatures on the next capture invocation with connectivity. The approved user experience has no manual sync step and no Mac or replacement recognition service dependency.

- When capture starts, the app shall start the new recording before processing its backlog.
- When recording finishes, the app shall persist a signature and stable capture identifier before reporting it saved.
- When invoked online, the app shall attempt current and pending signatures with ShazamKit within the available execution lifetime.
- If connectivity or runtime ends, the app shall retain unfinished work for subsequent use.
- When recognition succeeds, the app shall persist matched metadata and enqueue a file-backed background URLSession upload to Music Sync.
- If delivery fails or the response does not confirm success, the app shall retain the match without repeating recognition.
- The system shall deduplicate repeated delivery by capture identifier and use revocable capture-only credentials stored in the iOS Keychain.
- The UI shall show capture, pending and completed states and provide endpoint/token configuration. No analytics by default.

Recognition uses the Shazam catalog over the network. Local signatures are stored as files; queue metadata uses SwiftData. App Intents execute inside the app, so no extension or App Group is required. The Capture song App Shortcut opens the app and immediately records a 15-second clip. An existing record-audio Shortcut can instead pass its file to the awaited Save audio capture intent without opening the UI. The app also offers a native capture button. Work is bounded; a large backlog can require multiple invocations.

Music Sync owns its capture endpoint, caller credentials and delivery receipts. The iOS app owns its local queue and consumes that API only. No provider credentials or backing-store access reach the app. Service changes are committed and reviewed before deployment approval.

Validation includes offline persistence across app relaunch, next-use processing, actual serialized Shazam signatures, interrupted matching, retryable upload responses, duplicates, malformed replies and real-device capture. Simulator checks do not prove microphone or catalog access on a provisioned phone.
