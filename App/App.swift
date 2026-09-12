import SwiftUI

@main
struct OfflineShazamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            switch Runtime.controller {
            case .success(let controller): ContentView(controller: controller)
            case .failure:
                ContentUnavailableView("Captures unavailable", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text("Unlock your iPhone and reopen the app. Existing captures have not been removed."))
            }
        }
    }
}
