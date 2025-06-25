import SwiftUI

struct MilestoneData: Identifiable {
    let id = UUID()
    var milestoneNumber: Int
    var targetWeightForMilestone: Double
    var displayLabel: String
    var isCompleted: Bool
    var progressToNextMilestone: Double
}

struct MilestoneView: View {
    let initialWeight: Double
    let currentWeight: Double
    let targetWeight: Double
    let numberOfMilestonesToShow: Int = 5

    private var isLosingWeightGoal: Bool {
        targetWeight < initialWeight
    }

    private var milestones: [MilestoneData] {
        var generatedMilestones: [MilestoneData] = []
        let totalWeightToChange = initialWeight - targetWeight

        guard abs(totalWeightToChange) > 0.01 else { return [] }

        let numSteps = max(1, numberOfMilestonesToShow)
        let idealStepValue = abs(totalWeightToChange) / Double(numSteps)
        var lastMilestoneWeight = initialWeight

        for i in 1...numSteps {
            let isFinalStep = (i == numSteps)
            let weightAtThisMilestoneTarget = isFinalStep ? targetWeight : (isLosingWeightGoal ? (initialWeight - (idealStepValue * Double(i))) : (initialWeight + (idealStepValue * Double(i))))
            
            let isCompleted = isLosingWeightGoal ? (currentWeight <= weightAtThisMilestoneTarget) : (currentWeight >= weightAtThisMilestoneTarget)
            
            var progressToNext: Double = 0.0
            if isCompleted {
                progressToNext = 1.0
            } else {
                let hasReachedStartOfSegment = isLosingWeightGoal ? (currentWeight < lastMilestoneWeight) : (currentWeight > lastMilestoneWeight)
                if hasReachedStartOfSegment {
                    let segmentTotalDistance = abs(weightAtThisMilestoneTarget - lastMilestoneWeight)
                    let progressWithinSegment = abs(currentWeight - lastMilestoneWeight)
                    if segmentTotalDistance > 0 {
                        progressToNext = min(max(0, progressWithinSegment / segmentTotalDistance), 1.0)
                    }
                }
            }

            let displayLabel = String(format: "%@%.1f lb", (isLosingWeightGoal ? "-" : "+"), abs(weightAtThisMilestoneTarget - lastMilestoneWeight))

            generatedMilestones.append(MilestoneData(
                milestoneNumber: i,
                targetWeightForMilestone: weightAtThisMilestoneTarget,
                displayLabel: displayLabel,
                isCompleted: isCompleted,
                progressToNextMilestone: progressToNext
            ))
            
            lastMilestoneWeight = weightAtThisMilestoneTarget
        }
        return generatedMilestones
    }

    private var completedMilestonesCount: Int {
        milestones.filter { $0.isCompleted }.count
    }
    
    private var totalMilestones: Int {
        milestones.count
    }

    var body: some View {
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
                    Text(String(format: "Initial: %.1f lb", initialWeight))
                    Spacer()
                    Text(String(format: "Goal: %.1f lb", targetWeight))
                }
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 5)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(15)
        .padding(.horizontal)
    }
}
