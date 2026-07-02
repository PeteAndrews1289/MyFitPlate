import SwiftUI

struct PlateCalculatorView: View {
    @State private var targetWeight: String = ""
    private var barbellWeight: Double = 45.0

    private var plates: [(weight: Double, count: Int)] {
        guard let weight = Double(targetWeight), weight > barbellWeight else { return [] }
        
        var remainingWeight = (weight - barbellWeight) / 2.0
        var plateCounts: [(Double, Int)] = []
        let standardPlates = [45.0, 25.0, 10.0, 5.0, 2.5]
        
        for plate in standardPlates where remainingWeight >= plate {
            let count = Int(remainingWeight / plate)
            plateCounts.append((plate, count))
            remainingWeight -= Double(count) * plate
        }
        return plateCounts
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Total weight on barbell")) {
                    TextField("e.g., 225 lb", text: $targetWeight)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Plates per side (45 lb barbell)")) {
                    if plates.isEmpty {
                        Text("Enter a weight greater than 45 lb.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(plates, id: \.weight) { plate in
                            HStack {
                                Text("\(String(format: "%g", plate.weight)) lb")
                                Spacer()
                                Text(plate.count.formatted())
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plate calculator")
        }
    }
}
