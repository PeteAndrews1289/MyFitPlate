import SwiftUI

@MainActor
public class SpotlightManager: ObservableObject {
    @Published private(set) var shownSpotlightIDs: Set<String> = []
    
    private let userDefaultsKey = "shownSpotlightIDs"
    
    public init() {
        loadShownSpotlights()
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
