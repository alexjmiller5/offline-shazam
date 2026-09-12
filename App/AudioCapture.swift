import AVFoundation
import ShazamKit

enum AudioCapture {
    static func signature(from url: URL) async throws -> SHSignature {
        guard url.isFileURL,
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 16 * 1024 * 1024 else { throw CaptureError.invalidAudio }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 30 else { throw CaptureError.invalidAudio }
        let signature = try await SHSignatureGenerator.signature(from: asset)
        guard signature.duration > 0 else { throw CaptureError.invalidAudio }
        return signature
    }
}

@MainActor
final class ShazamMatcher: NSObject, SHSessionDelegate {
    let session: SHSession
    private var continuation: CheckedContinuation<MatchMetadata?, Error>?
    private var timeout: Task<Void, Never>?

    init(session: SHSession = SHSession()) {
        self.session = session
        super.init()
    }

    func match(_ data: Data) async throws -> MatchMetadata? {
        let signature = try SHSignature(dataRepresentation: data)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                session.delegate = self
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(6)) }
                    catch { return }
                    self?.finish(.failure(URLError(.timedOut)))
                }
                session.match(signature)
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<MatchMetadata?, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        session.delegate = nil
        continuation.resume(with: result)
    }

    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        let item = match.mediaItems.first
        let metadata = item.flatMap { item -> MatchMetadata? in
            guard let title = item.title, let artist = item.artist else { return nil }
            return MatchMetadata(title: title, artist: artist, appleMusicID: item.appleMusicID,
                                 shazamURL: item.webURL?.absoluteString, appleMusicURL: item.appleMusicURL?.absoluteString, isrc: item.isrc)
        }
        Task { @MainActor in
            if let metadata { self.finish(.success(metadata)) }
            else { self.finish(.failure(CaptureError.missingMetadata)) }
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        Task { @MainActor in
            if let error { self.finish(.failure(error)) }
            else { self.finish(.success(nil)) }
        }
    }
}

enum CaptureError: LocalizedError {
    case invalidAudio, missingMetadata, alreadyRecording, microphoneDenied, recordingInterrupted
    var errorDescription: String? {
        switch self {
        case .invalidAudio: return "Use a readable audio clip up to 30 seconds long."
        case .missingMetadata: return "Shazam returned incomplete song details. The capture is saved for another attempt."
        case .alreadyRecording: return "A capture is already in progress."
        case .microphoneDenied: return "Allow microphone access in iPhone Settings to capture music."
        case .recordingInterrupted: return "The recording was interrupted before it was saved. Please try again."
        }
    }
}
