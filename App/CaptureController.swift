import Foundation
import Observation
import ShazamKit

@MainActor @Observable
final class CaptureController {
    let store: CaptureStore
    let delivery: DeliveryService
    let recordAudio: () async throws -> CapturedAudio
    let processor: CaptureProcessor
    var isOnline = true
    var isRecording = false
    var isProcessing = false
    var records: [CaptureRecord] = []
    var status: String?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var processingID: UUID?

    init(store: CaptureStore, delivery: DeliveryService,
         recordAudio: @escaping () async throws -> CapturedAudio,
         recognize: @escaping (Data) async throws -> MatchMetadata?) {
        self.store = store
        self.delivery = delivery
        self.recordAudio = recordAudio
        processor = CaptureProcessor(store: store, recognize: recognize)
        refresh()
    }

    func capture() async throws -> CaptureRecord {
        guard !isRecording else { throw CaptureError.alreadyRecording }
        status = nil
        processingTask?.cancel()
        let record = try await recordAndSave()
        status = "Capture saved."
        refresh()
        await resume(preferred: record.id)
        return record
    }

    private func recordAndSave() async throws -> CaptureRecord {
        isRecording = true
        defer { isRecording = false }
        let audio = try await recordAudio()
        let record = try store.capture(signature: audio.signature)
        if let metadata = audio.metadata { try store.matched(record, metadata: metadata) }
        return record
    }

    func importAudio(_ url: URL) async throws -> CaptureRecord {
        let signature = try await AudioCapture.signature(from: url)
        let record = try store.capture(signature: signature)
        status = "Capture saved."
        refresh()
        await resume(preferred: record.id)
        return record
    }

    func refresh() {
        do { records = try store.records() }
        catch { status = "Could not read saved captures. Reopen the app to try again." }
    }

    func resume(preferred: UUID? = nil) async {
        guard !isRecording || preferred != nil else { return }
        while let existing = processingTask {
            guard preferred != nil else { return }
            let existingID = processingID
            existing.cancel()
            await existing.value
            if processingID == existingID {
                processingTask = nil
                processingID = nil
                isProcessing = false
            }
        }
        guard !Task.isCancelled else { return }
        let id = UUID()
        processingID = id
        isProcessing = true
        let task = Task { @MainActor in
            do {
                try Task.checkCancellation()
                await enqueueMatches()
                if isOnline {
                    try await processor.process(preferred: preferred) { await self.enqueueMatches() }
                }
            } catch is CancellationError {
                // Cancellation leaves durable work for the next invocation.
            } catch {
                status = "Saved captures will continue on your next use."
            }
            refresh()
        }
        processingTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if processingID == id {
            processingTask = nil
            processingID = nil
            isProcessing = false
        }
    }

    private func enqueueMatches() async {
        refresh()
        do { try await delivery.enqueue() }
        catch { status = "Saved captures will continue on your next use." }
    }
}
