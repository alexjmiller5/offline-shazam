import Foundation

struct MatchMetadata: Equatable, Sendable {
    let title: String
    let artist: String
    var appleMusicID: String? = nil
    var shazamURL: String? = nil
    var appleMusicURL: String? = nil
    var isrc: String? = nil
}

@MainActor
final class CaptureProcessor {
    let store: CaptureStore
    let recognize: (Data) async throws -> MatchMetadata?
    private var processing = false

    init(store: CaptureStore, recognize: @escaping (Data) async throws -> MatchMetadata?) {
        self.store = store
        self.recognize = recognize
    }

    func process(preferred: UUID? = nil, limit: Int = 3) async throws {
        guard !processing, limit > 0 else { return }
        processing = true
        defer { processing = false }
        let pending = try store.records().filter { $0.state == .pending }.sorted {
            if $0.id == $1.id { return false }
            if $0.id == preferred { return true }
            if $1.id == preferred { return false }
            let left = $0.lastAttemptAt ?? .distantPast
            let right = $1.lastAttemptAt ?? .distantPast
            return left == right ? $0.createdAt < $1.createdAt : left < right
        }
        for record in pending.prefix(limit) {
            try Task.checkCancellation()
            record.lastAttemptAt = Date()
            do {
                if let metadata = try await recognize(store.signature(for: record)) {
                    try store.matched(record, metadata: metadata)
                } else {
                    record.state = .unmatched
                    record.lastError = "Shazam could not identify this recording."
                }
            } catch {
                record.lastError = "Recognition interrupted. Saved for next use."
                try store.save()
                if error is CancellationError { throw error }
            }
            try store.save()
        }
    }
}
