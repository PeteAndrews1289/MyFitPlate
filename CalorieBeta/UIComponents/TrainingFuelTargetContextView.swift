import MyFitPlateCore
import SwiftUI

struct TrainingFuelTargetContextView: View {
    let target: TrainingFuelTarget
    var currentCalories: Double?
    var currentProtein: Double?
    var currentCarbs: Double?
    var onDismiss: (() -> Void)?

    init(
        target: TrainingFuelTarget,
        currentCalories: Double? = nil,
        currentProtein: Double? = nil,
        currentCarbs: Double? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.target = target
        self.currentCalories = currentCalories
        self.currentProtein = currentProtein
        self.currentCarbs = currentCarbs
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: target.phase.symbol)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.brandForeground)
                    .frame(width: 34, height: 34)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(phaseTitle)
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text(target.sessionTitle)
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear training fuel target")
                }
            }

            HStack(spacing: 8) {
                metric(title: "Calories", value: "\(target.calories) cal", current: currentCalories)
                metric(title: "Protein", value: "\(target.proteinGrams) g", current: currentProtein)
                metric(title: "Carbs", value: "\(target.carbGrams) g", current: currentCarbs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.quiet, padding: AppSpacing.row)
    }

    private var phaseTitle: String {
        target.phase.title + " target"
    }

    private func metric(
        title: String,
        value: String,
        current: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appTextRole(.caption)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(current.map { "\(Int($0.rounded())) / \(value)" } ?? value)
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
