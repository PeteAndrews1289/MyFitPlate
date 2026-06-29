import SwiftUI
import ActivityKit

struct PlateMathVisualizer: View {
    let totalWeight: Double
    let barWeight: Double = 45.0

    // Standard plates in lbs
    let availablePlates: [Double] = [45, 35, 25, 10, 5, 2.5]

    // Calculate plates per side
    var platesPerSide: [Double] {
        var remainingWeight = (totalWeight - barWeight) / 2.0
        var plates: [Double] = []

        if remainingWeight <= 0 { return [] }

        for plate in availablePlates {
            while remainingWeight >= plate {
                plates.append(plate)
                remainingWeight -= plate
            }
        }
        return plates
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Plate Math")
                .appFont(size: 20, weight: .bold)

            if totalWeight < barWeight {
                Text("Weight must be at least \(Int(barWeight)) lbs (the bar).")
                    .foregroundColor(.secondary)
            } else {
                Text("Load this on **EACH SIDE**")
                    .appFont(size: 14)
                    .foregroundColor(.secondary)

                HStack(spacing: 2) {
                    // The Barbell Sleeve
                    Rectangle()
                        .fill(Color(UIColor.systemGray3))
                        .frame(width: 40, height: 20)
                        .cornerRadius(2)

                    // The Collar
                    Rectangle()
                        .fill(Color(UIColor.systemGray2))
                        .frame(width: 10, height: 40)
                        .cornerRadius(2)

                    // The Plates
                    ForEach(0..<platesPerSide.count, id: \.self) { index in
                        PlateView(weight: platesPerSide[index])
                    }

                    if platesPerSide.isEmpty {
                        Text("Just the bar!")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 5, y: 3)
            }
        }
        .padding()
    }
}

struct PlateView: View {
    let weight: Double

    private var plateColor: Color {
        switch weight {
        case 45: return .blue
        case 35: return .yellow
        case 25: return .green
        case 10: return .gray
        case 5: return .orange
        case 2.5: return .red
        default: return .gray
        }
    }

    private var plateHeight: CGFloat {
        switch weight {
        case 45: return 120
        case 35: return 100
        case 25: return 80
        case 10: return 60
        case 5: return 40
        case 2.5: return 30
        default: return 50
        }
    }

    private var plateWidth: CGFloat {
        switch weight {
        case 45: return 24
        case 35: return 22
        case 25: return 20
        case 10: return 18
        case 5: return 14
        case 2.5: return 12
        default: return 16
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(plateColor)
                .frame(width: plateWidth, height: plateHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                )

            Text(weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : "\(weight, specifier: "%.1f")")
                .appFont(size: 8, weight: .bold)
                .foregroundColor(.white)
                .rotationEffect(.degrees(-90))
        }
    }
}
