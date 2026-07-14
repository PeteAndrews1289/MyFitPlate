import MyFitPlateCore
import SwiftUI

struct CycleTrackingView: View {
    @EnvironmentObject var cycleService: CycleTrackingService
    @State private var showingCycleSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Cycle Context",
                    title: "Cycle Phase",
                    subtitle: "A calendar estimate based on your most recent period start."
                ) {
                    cycleOptionsMenu
                }

                if let cycleDay = cycleService.cycleDay {
                    CyclePhaseRingView(
                        cycleDay: cycleDay,
                        cycleLength: cycleService.cycleSettings.typicalCycleLength
                    )

                    if cycleService.isLoadingInsight {
                        HStack(spacing: AppSpacing.row) {
                            ProgressView()
                            Text("Preparing Maia guidance")
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface(.quiet)
                    } else if let insight = cycleService.aiInsight {
                        MaiaCycleInsightCard(insight: insight)
                    }
                } else {
                    noCycleContent
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .accessibilityIdentifier("cycle_tracking_screen")
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            if !ScreenshotDemoMode.isEnabled {
                cycleService.fetchAIInsight()
            }
        }
        .sheet(isPresented: $showingCycleSettings) {
            NavigationStack {
                CycleSettingsView(cycleSettings: $cycleService.cycleSettings)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingCycleSettings = false
                            }
                        }
                    }
            }
        }
    }

    private var cycleOptionsMenu: some View {
        Menu {
            Button("Log Period Start", systemImage: "calendar.badge.plus") {
                cycleService.logPeriodStart()
            }

            Button("Cycle Settings", systemImage: "slider.horizontal.3") {
                showingCycleSettings = true
            }

            if cycleService.cycleDay != nil {
                Button("Clear Last Period Start", systemImage: "trash", role: .destructive) {
                    cycleService.clearLastPeriodStart()
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .accessibilityLabel("Cycle Options")
        }
        .buttonStyle(AppIconButtonStyle(.neutral))
        .accessibilityIdentifier("cycle_options_button")
    }

    private var noCycleContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            GuidanceEmptyState(
                icon: "calendar.badge.clock",
                title: "No Cycle Logged Yet",
                message: "Log your latest period start to create a private calendar estimate."
            )

            VStack(spacing: AppSpacing.row) {
                Button("Log Period Start") {
                    cycleService.logPeriodStart()
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .accessibilityIdentifier("log_period_start_button")

                Button("Adjust Cycle Settings") {
                    showingCycleSettings = true
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
            }
        }
    }
}

struct CyclePhaseRingView: View {
    let cycleDay: CycleDay
    let cycleLength: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let phaseColors: [MenstrualPhase: Color] = [
        .menstrual: .pink,
        .follicular: AppPalette.brand,
        .ovulatory: .blue,
        .luteal: .orange
    ]

    private var progress: Double {
        min(max(Double(cycleDay.cycleDayNumber) / Double(max(cycleLength, 1)), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppSectionHeader(title: "Estimated Phase", subtitle: "Day \(cycleDay.cycleDayNumber) of a typical \(cycleLength)-day cycle")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.section) {
                        phaseRing
                        phaseSummary
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.group) {
                        phaseRing
                            .frame(maxWidth: .infinity)
                        phaseSummary
                    }
                }
            }
            .appSurface(.emphasized)

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppSectionHeader(title: "Phase Map", subtitle: "Typical timing, not a fertility prediction")

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: AppSpacing.row) {
                            ForEach(MenstrualPhase.allCases) { phase in
                                phaseLegendItem(phase)
                            }
                        }
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            alignment: .leading,
                            spacing: AppSpacing.group
                        ) {
                            ForEach(MenstrualPhase.allCases) { phase in
                                phaseLegendItem(phase)
                            }
                        }
                    }
                }
                .appSurface(.quiet)
            }
        }
    }

    private var phaseRing: some View {
        ZStack {
            Circle()
                .stroke(AppPalette.separator, lineWidth: 12)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    phaseColors[cycleDay.phase, default: .secondary],
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("Day \(cycleDay.cycleDayNumber)")
                    .appFont(size: 23, weight: .bold)
                    .foregroundStyle(AppPalette.text)
                    .monospacedDigit()

                Text(cycleDay.phase.rawValue.capitalized)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 148, height: 148)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day \(cycleDay.cycleDayNumber), estimated \(cycleDay.phase.rawValue) phase")
    }

    private var phaseSummary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            Text(cycleDay.phase.rawValue.capitalized)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)

            Text(phaseDescription(cycleDay.phase))
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: progress)
                .tint(phaseColors[cycleDay.phase, default: AppPalette.brand])

            Text("Based on your saved cycle average")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func phaseLegendItem(_ phase: MenstrualPhase) -> some View {
        HStack(spacing: AppSpacing.row) {
            Circle()
                .fill(phaseColors[phase, default: .secondary])
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(phase.rawValue.capitalized)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                Text(phaseDescription(phase))
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func phaseDescription(_ phase: MenstrualPhase) -> String {
        switch phase {
        case .menstrual: "Period days"
        case .follicular: "After your period"
        case .ovulatory: "Mid-cycle estimate"
        case .luteal: "Before your next period"
        }
    }
}
