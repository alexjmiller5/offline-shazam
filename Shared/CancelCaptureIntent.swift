import AppIntents
import Foundation

#if os(iOS)
typealias CancelCaptureIntentKind = LiveActivityIntent
#else
typealias CancelCaptureIntentKind = AppIntent
#endif

struct CancelCaptureIntent: CancelCaptureIntentKind {
    static var title: LocalizedStringResource = "Cancel song capture"
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "Recording")
    var recordingID: String

    init() {}

    init(recordingID: UUID) {
        self.recordingID = recordingID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // LiveActivityIntent runs in the containing app process. The widget
        // includes this declaration to describe its button without sharing state.
        #if !WIDGET_EXTENSION
        if let id = UUID(uuidString: recordingID) {
            try Runtime.controller.get().cancelCapture(id: id)
        }
        #endif
        return .result()
    }
}
