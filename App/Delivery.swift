import Foundation

@MainActor
final class DeliveryService: NSObject, URLSessionDataDelegate {
    let store: CaptureStore
    let uploadDirectory: URL
    let connection: () throws -> DeliveryConfiguration?
    let sessionConfiguration: URLSessionConfiguration
    let retryDelay: TimeInterval
    var onChange: (() -> Void)?
    var backgroundCompletion: (() -> Void)?
    private(set) var connectionIssue: String?
    private(set) var uploadingIDs: Set<UUID> = []
    private var responses: [Int: Data] = [:]
    private var currentConfiguration: DeliveryConfiguration?
    private var enqueuing = false
    private var enqueueAgain = false
    private var changingConnection = false
    private var supersededTaskIDs: Set<Int> = []
    private var retryTask: Task<Void, Never>?
    private var invalidated = false
    lazy var session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: .main)

    init(store: CaptureStore, uploadDirectory: URL, connection: @escaping () throws -> DeliveryConfiguration?,
         sessionConfiguration: URLSessionConfiguration, retryDelay: TimeInterval = 30) {
        self.store = store
        self.uploadDirectory = uploadDirectory
        self.connection = connection
        self.sessionConfiguration = sessionConfiguration
        self.retryDelay = max(0.01, retryDelay)
        super.init()
        do {
            currentConfiguration = try connection()
            if currentConfiguration == nil { connectionIssue = "Connect Music Sync in Settings to add songs to Spotify." }
            else if try store.records().contains(where: { $0.state == .matched && $0.deliveryBlocked }) {
                connectionIssue = "Connection needs attention in Settings."
            }
        } catch { connectionIssue = error.localizedDescription }
    }

    func enqueue() async throws {
        guard !invalidated, !changingConnection else { return }
        guard !enqueuing else { enqueueAgain = true; return }
        enqueuing = true
        retryTask?.cancel()
        retryTask = nil
        defer {
            enqueuing = false
            onChange?()
            if enqueueAgain {
                enqueueAgain = false
                Task { try? await enqueue() }
            }
        }
        do {
            let tasks = await currentTasks()
            guard !invalidated, !changingConnection else { return }
            uploadingIDs = Set(tasks.filter { $0.state != .completed && !supersededTaskIDs.contains($0.taskIdentifier) }
                .compactMap { $0.taskDescription.flatMap(UUID.init(uuidString:)) })
            let configuration = try connection()
            currentConfiguration = configuration
            guard let configuration else {
                connectionIssue = "Connect Music Sync in Settings to add songs to Spotify."
                return
            }
            let records = try store.records().filter { $0.state == .matched }
            guard !records.contains(where: \.deliveryBlocked) else {
                connectionIssue = "Connection needs attention in Settings."
                return
            }
            connectionIssue = nil
            try FileManager.default.createDirectory(at: uploadDirectory, withIntermediateDirectories: true)
            for record in records {
                guard !uploadingIDs.contains(record.id),
                      record.nextAttemptAt.map({ $0 <= Date() }) ?? true,
                      let metadata = record.metadata else { continue }
                let file = uploadFile(record.id)
                try CapturePayload(id: record.id, metadata: metadata).data().write(
                    to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                var request = URLRequest(url: configuration.endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization")
                let task = session.uploadTask(with: request, fromFile: file)
                task.taskDescription = record.id.uuidString
                uploadingIDs.insert(record.id)
                task.resume()
            }
            let next = records.filter { !uploadingIDs.contains($0.id) && $0.metadata != nil }
                .compactMap(\.nextAttemptAt).min()
            if let next { scheduleRetry(at: next) }
        } catch {
            connectionIssue = error.localizedDescription
            scheduleRetry(at: Date().addingTimeInterval(retryDelay))
            throw error
        }
    }

    func connectionChanged() async throws {
        changingConnection = true
        currentConfiguration = nil
        retryTask?.cancel()
        retryTask = nil
        for task in await currentTasks() {
            supersededTaskIDs.insert(task.taskIdentifier)
            task.cancel()
        }
        uploadingIDs.removeAll()
        defer { changingConnection = false; onChange?() }
        for record in try store.records() where record.state == .matched {
            record.nextAttemptAt = nil
            record.deliveryBlocked = false
            record.lastError = nil
        }
        try store.save()
        changingConnection = false
        try await enqueue()
    }

    private func scheduleRetry(at date: Date) {
        retryTask?.cancel()
        guard !invalidated else { return }
        // A suspended app resumes this deadline when iOS lets it execute again.
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(min(86400, max(0, date.timeIntervalSinceNow)))) }
            catch { return }
            guard let self else { return }
            self.retryTask = nil
            try? await self.enqueue()
        }
    }

    private func currentTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
    }

    private func uploadFile(_ id: UUID) -> URL {
        uploadDirectory.appendingPathComponent(id.uuidString + ".json")
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated {
            var body = responses[dataTask.taskIdentifier] ?? Data()
            guard body.count + data.count <= 64 * 1024 else {
                dataTask.cancel()
                return
            }
            body.append(data)
            responses[dataTask.taskIdentifier] = body
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            let body = responses.removeValue(forKey: task.taskIdentifier) ?? Data()
            guard supersededTaskIDs.remove(task.taskIdentifier) == nil,
                  let configuration = currentConfiguration,
                  task.originalRequest?.url == configuration.endpoint,
                  task.originalRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer " + configuration.token else { return }
            guard let description = task.taskDescription, let id = UUID(uuidString: description) else { return }
            uploadingIDs.remove(id)
            defer { onChange?() }
            do {
                if let record = try store.records().first(where: { $0.id == id }) {
                    let response = task.response as? HTTPURLResponse
                    try store.deliveryFinished(record, status: error == nil ? response?.statusCode ?? 0 : 0,
                                               data: body, retryAfter: response?.value(forHTTPHeaderField: "Retry-After"),
                                               retryDelay: retryDelay)
                }
                try? FileManager.default.removeItem(at: uploadFile(id))
                Task { try? await enqueue() }
            } catch {
                connectionIssue = "Could not update delivery. Your song is saved for another attempt."
                scheduleRetry(at: Date().addingTimeInterval(retryDelay))
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        MainActor.assumeIsolated {
            invalidated = true
            retryTask?.cancel()
            retryTask = nil
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            let completion = backgroundCompletion
            backgroundCompletion = nil
            completion?()
        }
    }
}
