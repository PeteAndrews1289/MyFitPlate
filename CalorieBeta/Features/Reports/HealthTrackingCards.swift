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
                        .fill(AppPalette.recovery.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "drop.fill")
                        .appFont(size: 20, weight: .semibold)
                        .foregroundColor(AppPalette.recovery)
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
    let weeklySteps: [Double?]
    let weeklyActiveEnergy: [Double?]
    let weeklyRestingHeartRate: [Double?]
    let weeklyHRV: [Double?]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Daily averages · includes today").appTextRole(.secondary).foregroundStyle(.secondary)
            healthRow("Steps", unit: "steps", readings: weeklySteps)
            Divider()
            healthRow("Active energy", unit: "cal", readings: weeklyActiveEnergy)
            Divider()
            healthRow("Resting heart rate", unit: "bpm", readings: weeklyRestingHeartRate)
            Divider()
            healthRow("Heart rate variability", unit: "ms", readings: weeklyHRV)
        }
        .appSurface(.quiet)
    }

    private func healthRow(_ title: String, unit: String, readings: [Double?]) -> some View {
        let values = readings.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
        let display = values.isEmpty ? "No readings" :
            (values.reduce(0, +) / Double(values.count)).formatted(.number.precision(.fractionLength(0))) + " " + unit
        return HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appTextRole(.body)
                if !values.isEmpty {
                    Text(values.count.formatted() + (values.count == 1 ? " recorded day" : " recorded days"))
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(display).appTextRole(.control).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + ", " + display)
        .accessibilityValue(values.isEmpty ? "" : values.count.formatted() + " recorded days")
    }
}
