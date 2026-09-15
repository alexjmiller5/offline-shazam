#if os(iOS)
import ActivityKit
#endif
import Foundation

#if os(iOS)
struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let startedAt: Date
        let deadline: Date
    }

    let recordingID: UUID
}
#else
struct RecordingAttributes {
    struct ContentState: Codable, Hashable {
        let startedAt: Date
        let deadline: Date
    }

    let recordingID: UUID
}
#endif
