
import SwiftUI

struct PlateCalculatorView: View {
    @State private var targetWeight: String = ""
    private var barbellWeight: Double = 45.0

    private var plates: [(weight: Double, count: Int)] {
        guard let weight = Double(targetWeight), weight > barbellWeight else { return [] }
        
        var remainingWeight = (weight - barbellWeight) / 2.0
        var plateCounts: [(Double, Int)] = []
        let standardPlates = [45.0, 25.0, 10.0, 5.0, 2.5]
        
        for plate in standardPlates {
            if remainingWeight >= plate {
                let count = Int(remainingWeight / plate)
                plateCounts.append((plate, count))
                remainingWeight -= Double(count) * plate
            }
        }
        return plateCounts
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Total Weight on Barbell")) {
                    TextField("e.g., 225 lbs", text: $targetWeight)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Plates Per Side (45lb Barbell)")) {
                    if plates.isEmpty {
                        Text("Enter a weight greater than 45 lbs.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(plates, id: \.weight) { plate in
                            HStack {
                                Text("\(String(format: "%g", plate.weight)) lb")
                                Spacer()
                                Text("\(plate.count)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plate Calculator")
        }
    }
}
