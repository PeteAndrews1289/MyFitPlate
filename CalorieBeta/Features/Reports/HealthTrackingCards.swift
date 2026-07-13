import MyFitPlateCore

import SwiftUI
import Charts

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
                    Text("Cycle tracking")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                    
                    if let cycleDay = cycleService.cycleDay {
                        Text("Day \(cycleDay.cycleDayNumber) - \(cycleDay.phase.rawValue.capitalized)")
                            .appFont(size: 14)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Log your period to get started")
                            .appFont(size: 14)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(AppSpacing.row)
            .appSurface(.quiet, padding: 0)
        }
        .buttonStyle(.plain)
    }
}

struct ComprehensiveHealthCard: View {
    let weeklySteps: [Double]
    let weeklyActiveEnergy: [Double]
    let weeklyRestingHeartRate: [Double]
    let weeklyHRV: [Double]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppSectionHeader(title: "Health trends", subtitle: "Last 7 days")
            
            VStack(spacing: 12) {
                healthRow(
                    icon: "shoeprints.fill",
                    color: .blue,
                    title: "Steps",
                    value: formattedWholeNumber(weeklySteps.last ?? 0),
                    unit: "steps",
                    trend: calculateTrend(weeklySteps)
                )
                
                Divider()
                
                healthRow(
                    icon: "flame.fill",
                    color: .orange,
                    title: "Active energy",
                    value: formattedWholeNumber(weeklyActiveEnergy.last ?? 0),
                    unit: "cal",
                    trend: calculateTrend(weeklyActiveEnergy)
                )
                
                Divider()
                
                healthRow(
                    icon: "heart.fill",
                    color: .red,
                    title: "Resting heart rate",
                    value: formattedWholeNumber(weeklyRestingHeartRate.last ?? 0),
                    unit: "bpm",
                    trend: calculateTrend(weeklyRestingHeartRate, lowerIsBetter: true)
                )
                
                Divider()
                
                healthRow(
                    icon: "waveform.path.ecg",
                    color: .purple,
                    title: "Heart rate variability",
                    value: formattedWholeNumber(weeklyHRV.last ?? 0),
                    unit: "ms",
                    trend: calculateTrend(weeklyHRV)
                )
            }
        }
        .appSurface(.quiet)
    }
    
    private func healthRow(icon: String, color: Color, title: String, value: String, unit: String, trend: Trend) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    healthLabel(icon: icon, color: color, title: title)
                    healthValue(value: value, unit: unit, trend: trend)
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    healthLabel(icon: icon, color: color, title: title)
                    Spacer()
                    healthValue(value: value, unit: unit, trend: trend)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value) \(unit)")
    }

    private func healthLabel(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 16, weight: .bold)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())

            Text(title)
                .appTextRole(.body)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func healthValue(value: String, unit: String, trend: Trend) -> some View {
        HStack(spacing: 6) {
            if trend != .neutral {
                Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                    .appFont(size: 10, weight: .bold)
                    .foregroundStyle(trend.color)
            }

            Text("\(value) \(unit)")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()
        }
    }
    
    enum Trend {
        case up, down, neutral
        
        var color: Color {
            switch self {
            case .up: return .accentPositive
            case .down: return .red
            case .neutral: return .secondary
            }
        }
    }
    
    private func calculateTrend(_ data: [Double], lowerIsBetter: Bool = false) -> Trend {
        let validData = data.filter { $0 > 0 }
        guard validData.count >= 2, let current = validData.last else { return .neutral }
        let previous = validData.dropLast().reduce(0, +) / Double(validData.count - 1)
        
        if current > previous * 1.05 {
            return lowerIsBetter ? .down : .up
        } else if current < previous * 0.95 {
            return lowerIsBetter ? .up : .down
        } else {
            return .neutral
        }
    }

    private func formattedWholeNumber(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}
