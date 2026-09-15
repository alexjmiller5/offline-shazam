import UserNotifications

@MainActor
final class CaptureNotifications {
    private let center: UNUserNotificationCenter
    private let authorization: () async -> UNAuthorizationStatus
    private let schedule: (UNNotificationRequest) async throws -> Void
    private var reconciliation: Task<Void, Never>?

    init(center: UNUserNotificationCenter = .current(),
         authorization: (() async -> UNAuthorizationStatus)? = nil,
         schedule: ((UNNotificationRequest) async throws -> Void)? = nil) {
        self.center = center
        self.authorization = authorization ?? { await center.notificationSettings().authorizationStatus }
        self.schedule = schedule ?? { try await center.add($0) }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func reconcile(store: CaptureStore) async {
        let previous = reconciliation
        let current = Task { @MainActor in
            await previous?.value
            await update(store: store)
        }
        reconciliation = current
        await current.value
    }

    private func update(store: CaptureStore) async {
        switch await authorization() {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications().map(\.request)
        guard let records = try? store.records() else { return }
        for record in records where record.state == .matched || record.state == .delivered {
            let identifier = "capture." + record.id.uuidString
            let existing = (pending + delivered).filter { $0.identifier == identifier }
            guard !record.deliveryNotificationScheduled,
                  record.state == .matched || record.notificationEligible || !existing.isEmpty,
                  let metadata = record.metadata else { continue }
            do {
                // Recover an OS-accepted request if the process stopped before SwiftData saved it.
                for request in existing {
                    if request.content.userInfo["stage"] as? String == "delivered" {
                        record.deliveryNotificationScheduled = true
                    } else if record.recognitionNotificationDate == nil,
                              let timestamp = request.content.userInfo["recognitionDate"] as? Double {
                        record.recognitionNotificationDate = Date(timeIntervalSince1970: timestamp)
                    }
                }
                if store.context.hasChanges { try store.save() }
                guard !record.deliveryNotificationScheduled else { continue }
                let isDelivered = record.state == .delivered
                guard isDelivered || record.recognitionNotificationDate == nil else { continue }
                let recognitionDate = Date().addingTimeInterval(10)
                let content = UNMutableNotificationContent()
                content.title = isDelivered ? "Added to Spotify" : "Song recognized"
                content.body = metadata.title + " by " + metadata.artist
                if !isDelivered { content.body += ". Saved for delivery." }
                // Same identifier per capture: a delayed confirmation replaces the
                // recognition card and alerts again, so one song never shows two cards.
                content.sound = .default
                content.interruptionLevel = .active
                content.userInfo = ["captureID": record.id.uuidString,
                                    "stage": isDelivered ? "delivered" : "recognized"]
                if !isDelivered { content.userInfo["recognitionDate"] = recognitionDate.timeIntervalSince1970 }
                // A nil trigger delivers immediately but can leave an older timed request pending.
                // A timed replacement cancels that request and also updates a delivered card by ID.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: isDelivered ? 1 : 10, repeats: false)
                try await schedule(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                record.notificationEligible = true
                if isDelivered { record.deliveryNotificationScheduled = true }
                else { record.recognitionNotificationDate = recognitionDate }
                try store.save()
            } catch {
                // Notification failure is optional; the next reconciliation retries without changing the song queue.
            }
        }
    }
}
