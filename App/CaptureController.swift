import Foundation
import Observation
import ShazamKit

@MainActor @Observable
final class CaptureController {
    let store: CaptureStore
    let delivery: DeliveryService
    let recordSignature: () async throws -> SHSignature
    let processor: CaptureProcessor
    var isOnline = true
    var isRecording = false
    var isProcessing = false
    var records: [CaptureRecord] = []
    var status: String?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var processingID: UUID?

    init(store: CaptureStore, delivery: DeliveryService,
         recordSignature: @escaping () async throws -> SHSignature,
         recognize: @escaping (Data) async throws -> MatchMetadata?) {
        self.store = store
        self.delivery = delivery
        self.recordSignature = recordSignature
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
        let signature = try await recordSignature()
        return try store.capture(signature: signature)
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
                if isOnline { try await processor.process(preferred: preferred) }
                try Task.checkCancellation()
                try await delivery.enqueue()
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
}
