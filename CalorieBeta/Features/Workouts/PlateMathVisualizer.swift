import MyFitPlateCore
import SwiftUI

struct PlateMathVisualizer: View {
    let totalWeight: Double
    var equipment: StrengthEquipment?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let equipment {
            NavigationStack {
                Form {
                    Section("Your equipment") {
                        Text(equipment.name ?? equipment.kind.title).appTextRole(.control)
                        LabeledContent("Set load", value: formatted(totalWeight, equipment: equipment))
                        Text(equipment.loadingMeaning.title).appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    if equipment.kind == .barbell {
                        Section("Load each side") {
                            LabeledContent("Bar", value: formatted(equipment.barWeight, equipment: equipment))
                            if let pairs = equipment.platePairs(for: totalWeight) {
                                if pairs.isEmpty { Text("Empty bar") } else {
                                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, plate in
                                        Text(formatted(plate, equipment: equipment))
                                    }
                                }
                                Text("Use these plates on each side of the bar. Only your available pairs are included.")
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                            } else {
                                Text("This load cannot be made with your available plates. Review the equipment or choose an available target.")
                                    .foregroundStyle(AppPalette.caution)
                            }
                        }
                    } else {
                        Section("Available weight") {
                            Text(equipment.contains(totalWeight)
                                 ? "This weight is listed in your equipment."
                                 : "This weight is not in your equipment list. Review the equipment or choose an available target.")
                                .appTextRole(.secondary)
                        }
                    }
                }
                .appFormStyle()
                .buttonStyle(AppListButtonStyle())
                .navigationTitle("Equipment details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        } else {
            PlateCalculatorView(initialTargetWeight: totalWeight, locksTarget: true)
        }
    }

    private func formatted(_ pounds: Double, equipment: StrengthEquipment) -> String {
        "\(equipment.unit.displayWeight(pounds).formatted(.number.precision(.fractionLength(0...2)))) \(equipment.unit.rawValue)"
    }
}
