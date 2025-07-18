import SwiftUI

@main
struct WatchAppApp: App {
    @WKApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appDelegate) // 👈 inject it globally
        }
    }
}
