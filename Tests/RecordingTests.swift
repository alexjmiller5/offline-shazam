import AVFoundation
import XCTest
@testable import OfflineShazam

@MainActor
final class RecordingTests: XCTestCase {
    func testDelayedCallbacksFromInterruptedRecorderCannotFinishTheNextRecording() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1]
        let old = try AVAudioRecorder(url: directory.appendingPathComponent("old.m4a"), settings: settings)
        let current = try AVAudioRecorder(url: directory.appendingPathComponent("current.m4a"), settings: settings)
        let recorder = AudioRecorder()
        let oldStarted = expectation(description: "first recording starts")
        let first = Task { @MainActor in
            try? await recorder.recordUntilFinished(using: old, start: { oldStarted.fulfill(); return true })
        }
        await fulfillment(of: [oldStarted], timeout: 1)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        await first.value
        let currentStarted = expectation(description: "second recording starts")
        var finished = false
        let second = Task { @MainActor in
            try? await recorder.recordUntilFinished(using: current, start: { currentStarted.fulfill(); return true })
            finished = true
        }
        await fulfillment(of: [currentStarted], timeout: 1)
        recorder.audioRecorderDidFinishRecording(old, successfully: true)
        recorder.audioRecorderEncodeErrorDidOccur(old, error: CaptureError.invalidAudio)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(finished, "A delayed callback from the old recorder must not finish the new capture")
        recorder.audioRecorderDidFinishRecording(current, successfully: true)
        await second.value
        XCTAssertTrue(finished)
    }

    func testAudioInterruptionEndsThePendingRecording() async {
        let recorder = AudioRecorder()
        let started = expectation(description: "recording started")
        let finished = expectation(description: "interruption finishes recording")
        var failure: Error?
        let task = Task { @MainActor in
            do { try await recorder.recordUntilFinished(start: { started.fulfill(); return true }) }
            catch { failure = error }
            finished.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                        object: AVAudioSession.sharedInstance(),
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(failure?.localizedDescription, CaptureError.recordingInterrupted.localizedDescription)
        task.cancel()
        await task.value
    }

    func testRecordingHasADeadlineWhenTheSystemNeverSendsCompletion() async {
        let recorder = AudioRecorder()
        let finished = expectation(description: "deadline finishes recording")
        var failure: Error?
        let task = Task { @MainActor in
            do { try await recorder.recordUntilFinished(start: { true }, timeout: .milliseconds(10)) }
            catch { failure = error }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(failure?.localizedDescription, CaptureError.recordingInterrupted.localizedDescription)
        task.cancel()
        await task.value
    }
}
