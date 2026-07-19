import SwiftUI

struct PlateMathVisualizer: View {
    let totalWeight: Double

    var body: some View {
        PlateCalculatorView(initialTargetWeight: totalWeight, locksTarget: true)
    }
}
