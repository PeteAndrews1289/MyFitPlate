import MyFitPlateCore

import SwiftUI

struct WorkoutInsightRowView: View {
    let insight: WorkoutAnalysisInsight

    private var iconName: String {
        switch insight.category {
        case "Performance": return "chart.bar.xaxis"
        case "Consistency": return "calendar.badge.clock"
        case "Recovery": return "moon.zzz.fill"
        case "Nutrition": return "fork.knife"
        case "Mindset": return "brain.head.profile"
        default: return "sparkle"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 34, height: 34)
                .background(AppPalette.brand.opacity(0.1), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.message)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, AppSpacing.row)
    }
}
