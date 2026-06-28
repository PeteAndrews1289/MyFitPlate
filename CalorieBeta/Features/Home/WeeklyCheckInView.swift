import SwiftUI
import FirebaseAuth

struct WeeklyCheckInView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var adaptiveGoalService: AdaptiveGoalService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    if adaptiveGoalService.dataConfidence == .high || adaptiveGoalService.dataConfidence == .medium {
                        statsSection
                        TrendDashboardView(weightHistory: goalSettings.weightHistory)
                        actionSection
                    } else {
                        needsDataSection
                    }
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Weekly Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Toolbar empty to enforce rigid check-in
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .appFont(size: 32, weight: .bold)
                .foregroundColor(.brandPrimary)
                .padding()
                .background(Color.brandPrimary.opacity(0.12), in: Circle())
            
            Text("Time for your check-in!")
                .appFont(size: 24, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Text("We've analyzed your weight and nutrition data from the past 3 weeks to adjust your metabolism estimate.")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 16)
    }
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your Data")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(adaptiveGoalService.dataConfidence.rawValue)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(adaptiveGoalService.dataConfidence.colorName))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(adaptiveGoalService.dataConfidence.colorName).opacity(0.12), in: Capsule())
            }
            
            HStack(spacing: 16) {
                WeeklyCheckInStatCard(
                    title: "Avg Intake",
                    value: adaptiveGoalService.last21DaysCalorieAverage != nil ? "\(Int(adaptiveGoalService.last21DaysCalorieAverage!))" : "--",
                    subtitle: "kcal / day",
                    icon: "fork.knife",
                    color: .orange
                )
                
                WeeklyCheckInStatCard(
                    title: "Weight Trend",
                    value: adaptiveGoalService.weightChangeRatePerDay != nil ? "\(String(format: "%.2f", adaptiveGoalService.weightChangeRatePerDay! * 7))" : "--",
                    subtitle: "lbs / week",
                    icon: "scalemass.fill",
                    color: .teal
                )
            }
            
            Divider()
            
            VStack(spacing: 8) {
                Text("Calculated TDEE")
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(adaptiveGoalService.calculatedTDEE != nil ? "\(Int(adaptiveGoalService.calculatedTDEE!))" : "--")
                        .appFont(size: 48, weight: .heavy)
                        .foregroundColor(.textPrimary)
                    Text(" kcal")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .asCard()
    }
    
    private var actionSection: some View {
        VStack(spacing: 12) {
            Button(action: acceptTargets) {
                Text("Accept New Targets")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            
            Button(action: skipCheckIn) {
                Text("Keep Current Targets")
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
    
    private var needsDataSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .appFont(size: 40)
                .foregroundColor(.gray)
            
            Text("Needs More Data")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Text("We need at least 7 days of weight data and 10 days of food logs to confidently adjust your TDEE.")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
            
            Button(action: skipCheckIn) {
                Text("Check back later")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(20)
        .asCard()
    }
    
    private func acceptTargets() {
        HapticManager.instance.feedback(.light)
        goalSettings.calorieGoalMethod = .dynamicTDEE
        goalSettings.lastCheckInDate = Date()
        goalSettings.recalculateAllGoals()
        if let userID = Auth.auth().currentUser?.uid {
            goalSettings.saveUserGoals(userID: userID)
        }
        dismiss()
    }
    
    private func skipCheckIn() {
        HapticManager.instance.feedback(.light)
        goalSettings.lastCheckInDate = Date()
        if let userID = Auth.auth().currentUser?.uid {
            goalSettings.saveUserGoals(userID: userID)
        }
        dismiss()
    }
}

private struct WeeklyCheckInStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .appFont(size: 16, weight: .bold)
                .foregroundColor(color)
                .padding(8)
                .background(color.opacity(0.12), in: Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(value)
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
import SwiftUI
import Charts

struct TrendDashboardView: View {
    var weightHistory: [(id: String, date: Date, weight: Double)]
    
    private var chartData: [(date: Date, weight: Double)] {
        // Filter to last 21 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -21, to: Date()) ?? Date()
        let recent = weightHistory.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        
        // Ensure we have data
        if recent.isEmpty {
            return weightHistory.suffix(7).map { (date: $0.date, weight: $0.weight) }
        }
        return recent.map { (date: $0.date, weight: $0.weight) }
    }

    // Exponential moving average — the actual "smoothed trend" the caption promises.
    private var smoothedData: [(date: Date, weight: Double)] {
        let raw = chartData
        guard let first = raw.first else { return [] }
        let alpha = 0.4
        var ema = first.weight
        return raw.map { point in
            ema = alpha * point.weight + (1 - alpha) * ema
            return (date: point.date, weight: ema)
        }
    }

    private var yAxisDomain: ClosedRange<Double> {
        let weights = chartData.map { $0.weight } + smoothedData.map { $0.weight }
        let minW = weights.min() ?? 150.0
        let maxW = weights.max() ?? 150.0
        let padding = max(1.5, (maxW - minW) * 0.4)
        return (minW - padding)...(maxW + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight Trend (21 Days)")
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Text("Your smoothed weight trend, adjusted for day-to-day fluctuations.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .padding(.bottom, 8)

            if chartData.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "scalemass")
                        .appFont(size: 28)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    Text("Log a few more weigh-ins")
                        .appFont(size: 15, weight: .semibold)
                        .foregroundColor(.textPrimary)
                    Text("Your trend line appears once you have at least two recent entries.")
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            } else {
                Chart {
                    // Real weigh-ins as subtle dots
                    ForEach(chartData, id: \.date) { item in
                        PointMark(
                            x: .value("Date", item.date),
                            y: .value("Weight", item.weight)
                        )
                        .foregroundStyle(Color(UIColor.tertiaryLabel))
                        .symbolSize(28)
                    }
                    // Smoothed trend: area + line
                    ForEach(smoothedData, id: \.date) { item in
                        AreaMark(
                            x: .value("Date", item.date),
                            y: .value("Weight", item.weight)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.brandPrimary.opacity(0.22), Color.brandPrimary.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Date", item.date),
                            y: .value("Weight", item.weight)
                        )
                        .foregroundStyle(Color.brandPrimary)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                }
                .chartYScale(domain: yAxisDomain)
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month().day())
                                    .appFont(size: 11)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text("\(Int(val))")
                                    .appFont(size: 11)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                    }
                }
                .frame(height: 200)
                .clipped()
            }
        }
        .padding(20)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
