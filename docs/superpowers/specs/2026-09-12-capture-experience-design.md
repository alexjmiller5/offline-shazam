# Capture experience

The app shall let the user cancel accidental recording from its capture control or recording Live Activity. Explicit cancellation discards the current capture; operating-system interruption preserves useful audio. Previously saved work remains durable.

The app shall distinguish missing Music Sync setup, rejected app credentials, temporary service errors, and unavailable internet. It shall resume queued deliveries on activation, reconnect, connection repair, and explicit Shortcut invocation. No manual sync is required. Saved configuration shall be checked against the service without adding a song.

On iOS 18 and later the Capture song Shortcut shall use AudioRecordingIntent and a Live Activity to record without foregrounding the app. The Live Activity shall show recording progress and cancellation in Dynamic Island and on the Lock Screen. The intent shall await its work. iOS 17 shall retain a supported foreground fallback unless a clean availability-safe implementation requires an iOS 18 minimum. A user force quit cancels system background transfers; a subsequent user invocation shall restore queued work. The app shall not claim it can bypass force quit.

Recognition shall schedule a notification after a short delivery grace period. Delivery within that period shall replace the pending notification with one combined recognized-and-added confirmation. Delayed delivery shall replace the same capture notification and alert again. Notification state shall survive process restart and retries shall not repeat completed alerts. Only validated server receipts permit Spotify success wording. Notifications use native authorization and remain optional if denied.

Use SwiftUI, ActivityKit, App Intents, UserNotifications, SwiftData and URLSession. No new recognition provider, analytics, backend sharing, or persistent microphone activity beyond a user-requested capture. Configuration and captured song data stay out of source control.
