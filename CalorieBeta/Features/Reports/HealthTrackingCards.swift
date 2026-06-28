import SwiftUI
import Charts
import FirebaseAuth

struct CycleTrackingCard: View {
    @EnvironmentObject var cycleService: CycleTrackingService
    
    var body: some View {
        NavigationLink(destination: CycleTrackingView()) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "drop.fill")
                        .appFont(size: 20, weight: .semibold)
                        .foregroundColor(.pink)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cycle Tracking")
                        .appFont(size: 16, weight: .semibold)
                        .foregroundColor(.textPrimary)
                    
                    if let cycleDay = cycleService.cycleDay {
                        Text("Day \(cycleDay.cycleDayNumber) • \(cycleDay.phase.rawValue.capitalized)")
                            .appFont(size: 14)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    } else {
                        Text("Log your period to get started")
                            .appFont(size: 14)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding()
            .asCard()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ComprehensiveHealthCard: View {
    let weeklySteps: [Double]
    let weeklyActiveEnergy: [Double]
    let weeklyRestingHeartRate: [Double]
    let weeklyHRV: [Double]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Health Trends")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("Last 7 Days")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            
            VStack(spacing: 12) {
                healthRow(
                    icon: "shoeprints.fill",
                    color: .brandPrimary,
                    title: "Steps",
                    value: String(format: "%.0f", weeklySteps.last ?? 0),
                    unit: "steps",
                    trend: calculateTrend(weeklySteps)
                )
                
                Divider()
                
                healthRow(
                    icon: "flame.fill",
                    color: .orange,
                    title: "Active Energy",
                    value: String(format: "%.0f", weeklyActiveEnergy.last ?? 0),
                    unit: "kcal",
                    trend: calculateTrend(weeklyActiveEnergy)
                )
                
                Divider()
                
                healthRow(
                    icon: "heart.fill",
                    color: .red,
                    title: "Resting Heart Rate",
                    value: String(format: "%.0f", weeklyRestingHeartRate.last ?? 0),
                    unit: "bpm",
                    trend: calculateTrend(weeklyRestingHeartRate, lowerIsBetter: true)
                )
                
                Divider()
                
                healthRow(
                    icon: "waveform.path.ecg",
                    color: .purple,
                    title: "Heart Rate Variability",
                    value: String(format: "%.0f", weeklyHRV.last ?? 0),
                    unit: "ms",
                    trend: calculateTrend(weeklyHRV)
                )
            }
        }
        .padding()
        .asCard()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private func healthRow(icon: String, color: Color, title: String, value: String, unit: String, trend: Trend) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .appFont(size: 16, weight: .bold)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())
            
            Text(title)
                .appFont(size: 15, weight: .medium)
                .foregroundColor(.textPrimary)
            
            Spacer()
            
            HStack(spacing: 6) {
                if trend != .neutral {
                    Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .appFont(size: 10, weight: .bold)
                        .foregroundColor(trend.color)
                }
                
                HStack(spacing: 0) {
                    Text(value).fontWeight(.bold)
                    Text(" \(unit)").appFont(size: 12).foregroundColor(.secondary)
                }
                .appFont(size: 16)
                .foregroundColor(.textPrimary)
            }
        }
    }
    
    enum Trend {
        case up, down, neutral
        
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .neutral: return .secondary
            }
        }
    }
    
    private func calculateTrend(_ data: [Double], lowerIsBetter: Bool = false) -> Trend {
        let validData = data.filter { $0 > 0 }
        guard validData.count >= 2 else { return .neutral }
        let current = validData.last!
        let previous = validData.dropLast().reduce(0, +) / Double(validData.count - 1)
        
        if current > previous * 1.05 {
            return lowerIsBetter ? .down : .up
        } else if current < previous * 0.95 {
            return lowerIsBetter ? .up : .down
        } else {
            return .neutral
        }
    }
}

