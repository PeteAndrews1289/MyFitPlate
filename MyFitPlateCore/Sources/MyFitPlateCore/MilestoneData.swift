import SwiftUI

public struct MilestoneData: Identifiable {
    public let id = UUID()
    public var milestoneNumber: Int
    public var targetWeightForMilestone: Double
    public var displayLabel: String
    public var isCompleted: Bool
    public var progressToNextMilestone: Double
}

public enum MilestoneGenerator {
    public static func makeMilestones(
        initialWeight: Double,
        currentWeight: Double,
        targetWeight: Double,
        numberOfMilestones: Int = 5,
        useMetric: Bool
    ) -> [MilestoneData] {
        var generatedMilestones: [MilestoneData] = []
        let totalWeightToChange = initialWeight - targetWeight

        guard abs(totalWeightToChange) > 0.01 else { return [] }

        let isLosingWeightGoal = targetWeight < initialWeight
        let numSteps = max(1, numberOfMilestones)
        let idealStepValue = abs(totalWeightToChange) / Double(numSteps)
        var lastMilestoneWeight = initialWeight

        for index in 1...numSteps {
            let isFinalStep = index == numSteps
            let milestoneTarget = targetWeightForMilestone(
                index: index,
                isFinalStep: isFinalStep,
                initialWeight: initialWeight,
                targetWeight: targetWeight,
                idealStepValue: idealStepValue,
                isLosingWeightGoal: isLosingWeightGoal
            )

            let isCompleted = isLosingWeightGoal ? currentWeight <= milestoneTarget : currentWeight >= milestoneTarget
            let progressToNext = progressToNextMilestone(
                currentWeight: currentWeight,
                lastMilestoneWeight: lastMilestoneWeight,
                milestoneTarget: milestoneTarget,
                isCompleted: isCompleted,
                isLosingWeightGoal: isLosingWeightGoal
            )

            let segmentLbs = abs(milestoneTarget - lastMilestoneWeight)
            let displayLabel = String(
                format: "%@%.1f %@",
                isLosingWeightGoal ? "-" : "+",
                BodyUnits.weightDisplayValue(lbs: segmentLbs, metric: useMetric),
                BodyUnits.weightUnit(metric: useMetric)
            )

            generatedMilestones.append(MilestoneData(
                milestoneNumber: index,
                targetWeightForMilestone: milestoneTarget,
                displayLabel: displayLabel,
                isCompleted: isCompleted,
                progressToNextMilestone: progressToNext
            ))

            lastMilestoneWeight = milestoneTarget
        }

        return generatedMilestones
    }

    private static func targetWeightForMilestone(
        index: Int,
        isFinalStep: Bool,
        initialWeight: Double,
        targetWeight: Double,
        idealStepValue: Double,
        isLosingWeightGoal: Bool
    ) -> Double {
        if isFinalStep {
            return targetWeight
        }
        let stepChange = idealStepValue * Double(index)
        return isLosingWeightGoal ? initialWeight - stepChange : initialWeight + stepChange
    }

    private static func progressToNextMilestone(
        currentWeight: Double,
        lastMilestoneWeight: Double,
        milestoneTarget: Double,
        isCompleted: Bool,
        isLosingWeightGoal: Bool
    ) -> Double {
        if isCompleted {
            return 1.0
        }

        let hasReachedStartOfSegment = isLosingWeightGoal
            ? currentWeight < lastMilestoneWeight
            : currentWeight > lastMilestoneWeight
        guard hasReachedStartOfSegment else { return 0.0 }

        let segmentTotalDistance = abs(milestoneTarget - lastMilestoneWeight)
        guard segmentTotalDistance > 0 else { return 0.0 }

        let progressWithinSegment = abs(currentWeight - lastMilestoneWeight)
        return min(max(0, progressWithinSegment / segmentTotalDistance), 1.0)
    }
}

public struct MilestoneView: View {
    public let initialWeight: Double
    public let currentWeight: Double
    public let targetWeight: Double
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    public let numberOfMilestonesToShow: Int = 5

    public init(initialWeight: Double, currentWeight: Double, targetWeight: Double) {
        self.initialWeight = initialWeight
        self.currentWeight = currentWeight
        self.targetWeight = targetWeight
    }

    private var milestones: [MilestoneData] {
        MilestoneGenerator.makeMilestones(
            initialWeight: initialWeight,
            currentWeight: currentWeight,
            targetWeight: targetWeight,
            numberOfMilestones: numberOfMilestonesToShow,
            useMetric: useMetric
        )
    }

    private var completedMilestonesCount: Int {
        milestones.filter { $0.isCompleted }.count
    }
    
    private var totalMilestones: Int {
        milestones.count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Milestones",
                subtitle: milestones.isEmpty
                    ? "Set an initial and target weight to create checkpoints."
                    : "\(completedMilestonesCount) of \(totalMilestones) checkpoints reached."
            )
            
            if milestones.isEmpty {
                Text("Your checkpoints will appear here once the goal has enough distance to measure.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppSpacing.group)
            } else {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        ForEach(Array(milestones.enumerated()), id: \.offset) { index, milestone in
                            milestoneRow(index: index, milestone: milestone)
                            if index < milestones.count - 1 { Divider() }
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: AppSpacing.compact) {
                        ForEach(Array(milestones.enumerated()), id: \.offset) { index, milestone in
                            milestoneColumn(index: index, milestone: milestone)
                        }
                    }
                }

                AppMetricStrip(items: [
                    AppMetricItem(
                        label: "Starting Weight",
                        value: BodyUnits.weightString(lbs: initialWeight, metric: useMetric),
                        accent: .secondary
                    ),
                    AppMetricItem(
                        label: "Target Weight",
                        value: BodyUnits.weightString(lbs: targetWeight, metric: useMetric)
                    )
                ])
            }
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("weight_milestones")
    }

    private func milestoneColumn(index: Int, milestone: MilestoneData) -> some View {
        VStack(spacing: AppSpacing.compact) {
            Image(systemName: milestoneIcon(milestone))
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(milestoneColor(milestone))

            Text(milestone.displayLabel)
                .appTextRole(.caption)
                .foregroundStyle(milestone.isCompleted ? AppPalette.text : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            ProgressView(value: milestone.progressToNextMilestone)
                .tint(milestoneColor(milestone))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checkpoint \(index + 1), \(milestone.displayLabel)")
        .accessibilityValue(milestone.isCompleted ? "Complete" : "\(Int((milestone.progressToNextMilestone * 100).rounded())) percent")
    }

    private func milestoneRow(index: Int, milestone: MilestoneData) -> some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: milestoneIcon(milestone))
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(milestoneColor(milestone))
                .frame(width: 36, height: 36)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Checkpoint \(index + 1)")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(milestone.displayLabel)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                ProgressView(value: milestone.progressToNextMilestone)
                    .tint(milestoneColor(milestone))
            }
        }
        .padding(.vertical, AppSpacing.compact)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checkpoint \(index + 1), \(milestone.displayLabel)")
        .accessibilityValue(milestone.isCompleted ? "Complete" : "\(Int((milestone.progressToNextMilestone * 100).rounded())) percent")
    }

    private func milestoneIcon(_ milestone: MilestoneData) -> String {
        if milestone.isCompleted { return "checkmark.circle.fill" }
        if milestone.progressToNextMilestone > 0 { return "figure.walk" }
        return "circle.dashed"
    }

    private func milestoneColor(_ milestone: MilestoneData) -> Color {
        if milestone.isCompleted { return AppPalette.positive }
        if milestone.progressToNextMilestone > 0 { return AppPalette.brand }
        return .secondary
    }
}
