import ActivityKit
import Foundation

enum RecordingActivityError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Allow Live Activities in this app's system settings to record from Shortcuts, or start a capture in the app."
    }
}

@MainActor
final class RecordingActivity {
    typealias End = @MainActor () async -> Void
    typealias Request = @MainActor (RecordingAttributes, RecordingAttributes.ContentState) async throws -> End

    private let request: Request
    private var finish: End?

    init(request: Request? = nil) {
        self.request = request ?? Self.requestActivity
    }

    func start(id: UUID) async throws {
        let now = Date()
        finish = try await request(RecordingAttributes(recordingID: id),
            .init(startedAt: now, deadline: now.addingTimeInterval(15)))
    }

    func end() async {
        let finish = finish
        self.finish = nil
        await finish?()
    }

    private static func requestActivity(attributes: RecordingAttributes,
                                        state: RecordingAttributes.ContentState) async throws -> End {
        // A force quit can leave an indicator behind. A fresh user invocation
        // starts a new capture and retires indicators from the previous process.
        for activity in Activity<RecordingAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw RecordingActivityError.unavailable }
        let activity: Activity<RecordingAttributes>
        do {
            activity = try Activity.request(attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.deadline), pushType: nil)
        } catch {
            throw RecordingActivityError.unavailable
        }
        return { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
