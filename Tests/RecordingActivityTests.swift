#if os(iOS)
import ActivityKit
import ShazamKit
import XCTest
@testable import OfflineShazam

@MainActor
final class RecordingActivityTests: XCTestCase {
    func testLiveActivitySurroundsRecordingAndEndsBeforeRecognition() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(directory: directory)
        let service = DeliveryService(store: store, uploadDirectory: directory.appendingPathComponent("uploads"),
            connection: { nil }, sessionConfiguration: .ephemeral)
        var events: [String] = []
        let activity = RecordingActivity { attributes, state in
            XCTAssertEqual(state.deadline.timeIntervalSince(state.startedAt), 15, accuracy: 0.01)
            events.append("activity")
            return { events.append("end") }
        }
        let controller = CaptureController(store: store, delivery: service, recordAudio: {
            XCTAssertEqual(events, ["activity"])
            events.append("record")
            return CapturedAudio(signature: SHSignatureGenerator().signature())
        }, recognize: { _ in
            XCTAssertEqual(events, ["activity", "record", "end"])
            events.append("recognize")
            return nil
        }, recordingActivity: activity)
        _ = try await controller.capture(requiresLiveActivity: true)
        XCTAssertEqual(events, ["activity", "record", "end", "recognize"])
        XCTAssertEqual(try store.records().count, 1)
        service.session.finishTasksAndInvalidate()
    }

    func testRequiredLiveActivityFailurePreventsRecordingButForegroundCaptureStillWorks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(directory: directory)
        let service = DeliveryService(store: store, uploadDirectory: directory.appendingPathComponent("uploads"),
            connection: { nil }, sessionConfiguration: .ephemeral)
        var recordings = 0
        let activity = RecordingActivity { _, _ in throw RecordingActivityError.unavailable }
        let controller = CaptureController(store: store, delivery: service, recordAudio: {
            recordings += 1
            return CapturedAudio(signature: SHSignatureGenerator().signature())
        }, recognize: { _ in nil }, recordingActivity: activity)
        controller.isOnline = false
        do { _ = try await controller.capture(requiresLiveActivity: true); XCTFail("Background recording requires its indicator") }
        catch { XCTAssertTrue(error is RecordingActivityError) }
        XCTAssertEqual(recordings, 0)
        XCTAssertFalse(controller.isRecording)
        XCTAssertTrue(try store.records().isEmpty)
        _ = try await controller.capture()
        XCTAssertEqual(recordings, 1)
        XCTAssertEqual(try store.records().count, 1)
        service.session.finishTasksAndInvalidate()
    }

    func testStaleActivityCancelCannotStopCurrentRecordingAndCancelEndsActivity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(directory: directory)
        let service = DeliveryService(store: store, uploadDirectory: directory.appendingPathComponent("uploads"),
            connection: { nil }, sessionConfiguration: .ephemeral)
        let started = expectation(description: "recording started")
        var activeID: UUID?
        var ended = false
        let activity = RecordingActivity { attributes, _ in
            activeID = attributes.recordingID
            return { ended = true }
        }
        let controller = CaptureController(store: store, delivery: service, recordAudio: {
            started.fulfill()
            try await Task.sleep(for: .seconds(5))
            return CapturedAudio(signature: SHSignatureGenerator().signature())
        }, recognize: { _ in nil }, recordingActivity: activity)
        let capture = Task { @MainActor in _ = try await controller.capture(requiresLiveActivity: true) }
        await fulfillment(of: [started], timeout: 1)
        controller.cancelCapture(id: UUID())
        XCTAssertTrue(controller.isRecording)
        XCTAssertFalse(ended)
        controller.cancelCapture(id: try XCTUnwrap(activeID))
        do { try await capture.value; XCTFail("The current activity must cancel recording") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(ended)
        XCTAssertTrue(try store.records().isEmpty)
        service.session.finishTasksAndInvalidate()
    }

    func testShortcutSupportsRecordingWithoutForegroundOnCurrentOS() throws {
        guard #available(iOS 18, *) else { throw XCTSkip("iOS 17 uses the foreground fallback") }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents"))
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let actions = try XCTUnwrap(metadata["actions"] as? [String: [String: Any]])
        let capture = try XCTUnwrap(actions["CaptureSongIntent"])
        XCTAssertEqual(capture["openAppWhenRun"] as? Bool, false)
        let protocols = try XCTUnwrap(capture["systemProtocols"] as? [String])
        XCTAssertTrue(protocols.contains("com.apple.link.systemProtocol.AudioRecording"))
        XCTAssertTrue(protocols.contains("com.apple.link.systemProtocol.SessionStarting"))
    }

    func testNewCaptureRetiresStaleNativeActivityAndEndDismissesCurrentOne() async throws {
        let previousID = UUID()
        let previous = RecordingActivity()
        try await previous.start(id: previousID)
        let old = Activity<RecordingAttributes>.activities.first { $0.attributes.recordingID == previousID }
        XCTAssertNotNil(old)
        let id = UUID()
        let activity = RecordingActivity()
        try await activity.start(id: id)
        XCTAssertFalse(old?.activityState == .active)
        let native = Activity<RecordingAttributes>.activities.first { $0.attributes.recordingID == id }
        XCTAssertNotNil(native)
        await activity.end()
        XCTAssertFalse(native?.activityState == .active)
        await previous.end()
    }
}
#endif
