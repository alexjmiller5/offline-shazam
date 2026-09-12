import Foundation

@MainActor
final class DeliveryService: NSObject, URLSessionDataDelegate {
    let store: CaptureStore
    let uploadDirectory: URL
    let connection: () throws -> DeliveryConfiguration?
    let sessionConfiguration: URLSessionConfiguration
    var onChange: (() -> Void)?
    var backgroundCompletion: (() -> Void)?
    private var responses: [Int: Data] = [:]
    private var enqueuing = false
    lazy var session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: .main)

    init(store: CaptureStore, uploadDirectory: URL, connection: @escaping () throws -> DeliveryConfiguration?, sessionConfiguration: URLSessionConfiguration) {
        self.store = store
        self.uploadDirectory = uploadDirectory
        self.connection = connection
        self.sessionConfiguration = sessionConfiguration
        super.init()
    }

    func enqueue() async throws {
        guard !enqueuing else { return }
        enqueuing = true
        defer { enqueuing = false }
        guard let configuration = try connection() else { return }
        let tasks = await currentTasks()
        let active = Set(tasks.compactMap(\.taskDescription))
        try FileManager.default.createDirectory(at: uploadDirectory, withIntermediateDirectories: true)
        for record in try store.records() where record.state == .matched {
            guard !active.contains(record.id.uuidString),
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
            task.resume()
        }
    }

    func connectionChanged() async throws {
        for task in await currentTasks() { task.cancel() }
        for record in try store.records() where record.state == .matched {
            record.nextAttemptAt = nil
        }
        try store.save()
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
            guard let description = task.taskDescription, let id = UUID(uuidString: description) else { return }
            defer { onChange?() }
            do {
                if let record = try store.records().first(where: { $0.id == id }) {
                    let response = task.response as? HTTPURLResponse
                    try store.deliveryFinished(record, status: error == nil ? response?.statusCode ?? 0 : 0,
                                               data: body, retryAfter: response?.value(forHTTPHeaderField: "Retry-After"))
                }
                try? FileManager.default.removeItem(at: uploadFile(id))
            } catch {
                // The durable matched record remains eligible for another attempt.
            }
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
