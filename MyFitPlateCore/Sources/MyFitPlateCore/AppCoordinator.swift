import SwiftUI

public class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()
    @Published public var currentRoute: Route = .home
    
    public init() {}
    
    public func handle(url: URL, appState: AppState) {
        // Implementation for handling URL routing
    }
}
