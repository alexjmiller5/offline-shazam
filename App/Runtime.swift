import Network
import UIKit

@MainActor
enum Runtime {
    static let backgroundIdentifier = (Bundle.main.bundleIdentifier ?? "offline-shazam") + ".delivery"
    static let connection = ConnectionStore()
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
                                           recognize: { try await ShazamMatcher().match($0) })
        return controller
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let monitor = NWPathMonitor()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = try? Runtime.controller.get().delivery.session
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let controller = try? Runtime.controller.get() else { return }
                let reconnected = !controller.isOnline && online
                controller.isOnline = online
                if reconnected, UIApplication.shared.applicationState == .active {
                    await controller.resume()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "offline-shazam.connectivity"))
        return true
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
