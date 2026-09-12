import AVFoundation
import ShazamKit
import XCTest
@testable import OfflineShazam

@MainActor
final class ControllerTests: XCTestCase {
    func testImportedAudioIsAttemptedBeforeReturningEvenWhenAnotherPassIsRunning() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(directory: directory)
        _ = try store.capture(signature: SHSignatureGenerator().signature())
        let service = DeliveryService(store: store, uploadDirectory: directory.appendingPathComponent("uploads"), connection: { nil }, sessionConfiguration: .ephemeral)
        let started = expectation(description: "older recognition started")
        var matches = 0
        let controller = CaptureController(store: store, delivery: service, recordSignature: {
            XCTFail("Import must not start another microphone recording")
            return SHSignatureGenerator().signature()
        }, recognize: { _ in
            matches += 1
            if matches == 1 { started.fulfill(); try await Task.sleep(for: .seconds(60)) }
            return MatchMetadata(title: "Example Song", artist: "Example Artist")
        })
        let previous = Task { await controller.resume() }
        await fulfillment(of: [started], timeout: 2)
        let url = directory.appendingPathComponent("capture.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 220500))
        buffer.frameLength = 220500
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(buffer.frameLength) { samples[index] = Float(sin(Double(index) * 0.07)) * 0.5 }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let imported = try await controller.importAudio(url)
        XCTAssertEqual(imported.state, .matched, "An import must not return while excluded from the current pass")
        previous.cancel()
        await previous.value
        service.session.finishTasksAndInvalidate()
    }

    func testStartingAnotherCaptureCancelsBacklogWithoutClearingTheNewRecordingState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(directory: directory)
        let service = DeliveryService(store: store, uploadDirectory: directory.appendingPathComponent("uploads"), connection: { nil }, sessionConfiguration: .ephemeral)
        let firstMatching = expectation(description: "first capture begins matching")
        let secondRecording = expectation(description: "second recording starts promptly")
        var recordings = 0
        var matches = 0
        var finishRecording: CheckedContinuation<Void, Never>?
        let controller = CaptureController(store: store, delivery: service, recordSignature: {
            recordings += 1
            if recordings == 2 {
                await withCheckedContinuation { continuation in
                    finishRecording = continuation
                    secondRecording.fulfill()
                }
            }
            return SHSignatureGenerator().signature()
        }, recognize: { _ in
            matches += 1
            if matches == 1 {
                firstMatching.fulfill()
                try await Task.sleep(for: .seconds(60))
            }
            return MatchMetadata(title: "Example Song", artist: "Example Artist")
        })
        let first = Task { @MainActor in _ = try await controller.capture() }
        await fulfillment(of: [firstMatching], timeout: 3)
        let second = Task { @MainActor in _ = try await controller.capture() }
        await fulfillment(of: [secondRecording], timeout: 3)
        _ = try await first.value
        XCTAssertTrue(controller.isRecording, "Finishing the previous request must not enable a third recording")
        finishRecording?.resume()
        _ = try await second.value
        XCTAssertFalse(controller.isRecording)
        XCTAssertEqual(recordings, 2)
        service.session.finishTasksAndInvalidate()
    }

    func testOfflineCaptureThenNextOnlineUseRecordsBeforeProcessingBacklog() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(directory: directory)
        let service = DeliveryService(store: store, uploadDirectory: directory.appendingPathComponent("uploads"), connection: { nil }, sessionConfiguration: .ephemeral)
        var events: [String] = []
        let controller = CaptureController(store: store, delivery: service, recordSignature: {
            events.append("record")
            return SHSignatureGenerator().signature()
        }, recognize: { _ in
            events.append("recognize")
            return MatchMetadata(title: "Example Song", artist: "Example Artist")
        })
        controller.isOnline = false
        let first = try await controller.capture()
        XCTAssertEqual(events, ["record"])
        XCTAssertEqual(first.state, .pending)
        XCTAssertEqual(try CaptureStore(directory: directory).records().count, 1)
        controller.isOnline = true
        _ = try await controller.capture()
        XCTAssertEqual(events, ["record", "record", "recognize", "recognize"])
        XCTAssertEqual(try store.records().filter { $0.state == .matched }.count, 2)
        service.session.finishTasksAndInvalidate()
    }

    func testFailedRecordingDoesNotClaimToSaveOrTouchTheBacklog() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(directory: directory)
        let service = DeliveryService(store: store, uploadDirectory: directory.appendingPathComponent("uploads"), connection: { nil }, sessionConfiguration: .ephemeral)
        let controller = CaptureController(store: store, delivery: service, recordSignature: {
            throw CaptureError.microphoneDenied
        }, recognize: { _ in
            XCTFail("Do not process a backlog ahead of the requested capture")
            return nil
        })
        do { _ = try await controller.capture(); XCTFail("The caller must receive the recording failure") }
        catch { XCTAssertEqual(error.localizedDescription, CaptureError.microphoneDenied.localizedDescription) }
        XCTAssertTrue(try store.records().isEmpty)
        XCTAssertFalse(controller.isRecording)
        service.session.finishTasksAndInvalidate()
    }
}
