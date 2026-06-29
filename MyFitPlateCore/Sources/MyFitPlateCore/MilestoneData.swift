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
        VStack(alignment: .leading, spacing: 10) {
            Text("Milestones")
                .font(.headline)
            
            if milestones.isEmpty {
                Text("Set an initial and target weight to see milestones.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical)
            } else {
                Text("\(completedMilestonesCount)/\(totalMilestones) Milestones Completed")
                    .font(.subheadline)
                    .foregroundColor(completedMilestonesCount == totalMilestones && totalMilestones > 0 ? .green : .gray)
                    .padding(.bottom, 10)

                GeometryReader { geometry in
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(milestones.indices, id: \.self) { index in
                            let milestone = milestones[index]
                            VStack(spacing: 5) {
                                Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : (milestone.progressToNextMilestone > 0 && milestone.progressToNextMilestone < 1 && !milestone.isCompleted ? "figure.walk" : "circle.dashed"))
                                    .font(milestone.isCompleted ? .title2 : .title3)
                                    .foregroundColor(milestone.isCompleted ? .green : (milestone.progressToNextMilestone > 0 && !milestone.isCompleted ? Color.accentColor.opacity(0.8) : .gray.opacity(0.5)))
                                    .frame(height: 30)

                                Text(milestone.displayLabel)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .foregroundColor(milestone.isCompleted ? .primary.opacity(0.8) : .gray)
                                
                                Capsule()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: (geometry.size.width - CGFloat(milestones.count - 1) * 10 - CGFloat(milestones.count * 10) ) / CGFloat(milestones.count) , height: 10)
                                    .overlay(
                                        GeometryReader { capsuleGeo in
                                            Capsule()
                                                .fill(LinearGradient(gradient: Gradient(colors: [Color.accentColor.opacity(0.6), Color.accentColor]), startPoint: .leading, endPoint: .trailing))
                                                .frame(width: capsuleGeo.size.width * CGFloat(milestone.progressToNextMilestone))
                                        }
                                        , alignment: .leading
                                    )
                                    .animation(.easeInOut, value: milestone.progressToNextMilestone)
                                    .padding(.top, 2)
                            }
                            .frame(width: (geometry.size.width - CGFloat(milestones.count - 1) * 10) / CGFloat(milestones.count))

                            if index < milestones.count - 1 {
                                Spacer().frame(width: 10)
                            }
                        }
                    }
                }
                .frame(height: 80)

                HStack {
                    Text("Initial: \(BodyUnits.weightString(lbs: initialWeight, metric: useMetric))")
                    Spacer()
                    Text("Goal: \(BodyUnits.weightString(lbs: targetWeight, metric: useMetric))")
                }
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 5)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(15)
        .padding(.horizontal)
    }
}
