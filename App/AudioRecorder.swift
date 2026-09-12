import AVFoundation
import ShazamKit

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var continuation: CheckedContinuation<Void, Error>?
    private var deadline: Task<Void, Never>?
    private var recordingID: UUID?

    func captureSignature() async throws -> SHSignature {
        guard recorder == nil else { throw CaptureError.alreadyRecording }
        let allowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { throw CaptureError.microphoneDenied }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        let audioSession = AVAudioSession.sharedInstance()
        defer {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            try? FileManager.default.removeItem(at: url)
        }
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try audioSession.setActive(true)
        let recording = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        try await recordUntilFinished(using: recording, start: { recording.record(forDuration: 15) })
        return try await AudioCapture.signature(from: url)
    }

    func recordUntilFinished(using source: AVAudioRecorder? = nil, start: () -> Bool, timeout: Duration = .seconds(17)) async throws {
        guard continuation == nil else { throw CaptureError.alreadyRecording }
        let id = UUID()
        recordingID = id
        recorder = source
        source?.delegate = self
        let observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated {
                guard self?.recordingID == id else { return }
                self?.recorder?.stop()
                self?.finish(.failure(CaptureError.recordingInterrupted))
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            source?.delegate = nil
            source?.stop()
            if recordingID == id {
                recorder = nil
                recordingID = nil
            }
        }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: timeout) }
                    catch { return }
                    guard self?.recordingID == id else { return }
                    self?.recorder?.stop()
                    self?.finish(.failure(CaptureError.recordingInterrupted))
                }
                if !start() { finish(.failure(CaptureError.invalidAudio)) }
            }
        } onCancel: {
            Task { @MainActor in
                guard self.recordingID == id else { return }
                self.recorder?.stop()
                self.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        continuation.resume(with: result)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            finish(flag ? .success(()) : .failure(CaptureError.invalidAudio))
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            finish(.failure(CaptureError.invalidAudio))
        }
    }
}
