import SwiftUI

@MainActor
public class SpotlightManager: ObservableObject {
    @Published private(set) var shownSpotlightIDs: Set<String> = []
    /// Bumped by `requestReplay()`. Screens observe this to restart their tour on demand
    /// (the "Replay feature tour" button) without relying on `onAppear` re-firing.
    @Published public private(set) var replayToken = 0

    private let userDefaultsKey = "shownSpotlightIDs"

    public init() {
        loadShownSpotlights()
    }

    /// Clear the seen flags and signal observers to restart their tour immediately.
    public func requestReplay() {
        resetSpotlights()
        replayToken &+= 1
    }
    
    public func isShown(id: String) -> Bool {
        shownSpotlightIDs.contains(id)
    }
    
    public func markAsShown(id: String) {
        shownSpotlightIDs.insert(id)
        saveShownSpotlights()
    }
    
    public func resetSpotlights() {
        shownSpotlightIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
    
    private func loadShownSpotlights() {
        let savedIDs = UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
        self.shownSpotlightIDs = Set(savedIDs)
    }
    
    private func saveShownSpotlights() {
        UserDefaults.standard.set(Array(self.shownSpotlightIDs), forKey: userDefaultsKey)
    }
}
