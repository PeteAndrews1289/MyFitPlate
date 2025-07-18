import SwiftUI

struct Spotlight: Identifiable, Equatable {
    var id: String
    var title: String
    var text: String
    var anchor: Anchor<CGRect>
    var shape: SpotlightShape = .rectangle
    
    static func == (lhs: Spotlight, rhs: Spotlight) -> Bool {
        return lhs.id == rhs.id
    }
}

enum SpotlightShape {
    case rectangle
    case circle
    case roundedRectangle(cornerRadius: CGFloat)
}

struct SpotlightPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    
    static func reduce(value: inout [String : Anchor<CGRect>], nextValue: () -> [String : Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func spotlight(id: String) -> some View {
        self.anchorPreference(key: SpotlightPreferenceKey.self, value: .bounds) { anchor in
            return [id: anchor]
        }
    }
}