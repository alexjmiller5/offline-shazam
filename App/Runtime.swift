import Network
import UIKit
import UserNotifications

@MainActor
enum Runtime {
    static let backgroundIdentifier = (Bundle.main.bundleIdentifier ?? "offline-shazam") + ".delivery"
    static let connection = ConnectionStore()
    static let notifications = CaptureNotifications()
    static let controller: Result<CaptureController, Error> = Result {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("offline-shazam", isDirectory: true)
        let store = try CaptureStore(directory: directory)
        let configuration = URLSessionConfiguration.background(withIdentifier: backgroundIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        let delivery = DeliveryService(store: store, uploadDirectory: directory.appendingPathComponent("uploads"),
                                       connection: { try connection.load() }, sessionConfiguration: configuration)
        let recorder = AudioRecorder()
        let controller = CaptureController(store: store, delivery: delivery,
                                           recordAudio: { try await recorder.capture() },
                                           recognize: { try await ShazamMatcher().match($0) },
                                           recordingActivity: RecordingActivity())
        controller.onRecordsChanged = { await notifications.reconcile(store: store) }
        delivery.onRecordsChanged = { await notifications.reconcile(store: store) }
        return controller
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let monitor = NWPathMonitor()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        _ = try? Runtime.controller.get().delivery.session
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let controller = try? Runtime.controller.get() else { return }
                let reconnected = !controller.isOnline && online
                controller.isOnline = online
                if reconnected {
                    await controller.resume()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "offline-shazam.connectivity"))
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == Runtime.backgroundIdentifier, let controller = try? Runtime.controller.get() else {
            completionHandler()
            return
        }
        controller.delivery.backgroundCompletion = completionHandler
        _ = controller.delivery.session
    }
}
