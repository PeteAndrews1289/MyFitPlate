import MyFitPlateCore

import SwiftUI

struct HomeQuickActionsView: View {
    @State private var showingTools = false
    @Binding var showingCoachingDashboard: Bool
    @Binding var showingMenuScanner: Bool
    @Binding var showingWeightEntrySheet: Bool
    @Binding var showingFastingSheet: Bool
    @Binding var showSettings: Bool

    var isMenuScannerEnabled: Bool
    var isMenuScannerSpotlightActive: Bool
    var waterIntake: Double
    var waterGoal: Double
    var canLogWater: Bool
    var onOpenWorkouts: () -> Void
    var onOpenMaia: () -> Void
    var onLogWater: () -> Void
    var onRepeatYesterdayMeals: () -> Void
    var showsWorkouts = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AppSpacing.compact),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text("Shortcuts")
                    .appTextRole(.control)
                    .fontWeight(.semibold)
                Spacer()
                Button { showingTools = true } label: {
                    Text("All tools").appTextRole(.secondary)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(AppPalette.text)
                .accessibilityIdentifier("home_all_tools")
            }

            LazyVGrid(columns: columns, spacing: AppSpacing.compact) {
                if canLogWater {
                    Button {
                        HapticManager.instance.feedback(.medium)
                        onLogWater()
                    } label: {
                        QuickActionButton(icon: "drop.fill", label: "Add water",
                            subtitle: waterGoal > 0 ? "\(Int(waterIntake.rounded()).formatted()) of \(Int(waterGoal.rounded()).formatted()) oz" : "\(Int(waterIntake.rounded()).formatted()) oz · tracking only")
                    }
                    .accessibilityLabel("Add 8 ounces of water")
                    .accessibilityValue(waterGoal > 0 ? "\(Int(waterIntake.rounded()).formatted()) of \(Int(waterGoal.rounded()).formatted()) ounces" : "\(Int(waterIntake.rounded()).formatted()) ounces, tracking only")
                    .accessibilityIdentifier("home_add_water_button")
                }

                if showsWorkouts {
                    Button {
                        HapticManager.instance.feedback(.light)
                        onOpenWorkouts()
                    } label: {
                        QuickActionButton(icon: "dumbbell.fill", label: "Workouts", subtitle: "Train or resume")
                    }
                    .accessibilityIdentifier("home_workouts_button")
                }

                Button {
                    HapticManager.instance.feedback(.light)
                    onRepeatYesterdayMeals()
                } label: {
                    QuickActionButton(icon: "clock.arrow.circlepath", label: "Copy yesterday", subtitle: "Review your meals")
                }
                .accessibilityIdentifier("home_repeat_previous_day")

                Button {
                    HapticManager.instance.feedback(.light)
                    showingWeightEntrySheet = true
                } label: {
                    QuickActionButton(icon: "scalemass", label: "Log weight", subtitle: "Track your trend")
                }
                .accessibilityIdentifier("home_log_weight_button")
            }
            .buttonStyle(.plain)

            HStack(spacing: AppSpacing.row) {
                Button {
                    HapticManager.instance.feedback(.light)
                    showingCoachingDashboard = true
                } label: {
                    Label("Daily strategy", systemImage: "brain.head.profile")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("home_coaching_button")

                Menu {
                    Button("Ask Maia", systemImage: "bubble.left.and.bubble.right") { onOpenMaia() }
                    if isMenuScannerEnabled {
                        Button("Scan a menu", systemImage: "menucard") { showingMenuScanner = true }
                    }
                    Button("Fasting", systemImage: "timer") { showingFastingSheet = true }
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .frame(minWidth: 72, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More daily actions")
                .accessibilityIdentifier("home_more_actions")
                .featureSpotlight(isActive: isMenuScannerEnabled && isMenuScannerSpotlightActive)
            }
            .appTextRole(.secondary)
            .foregroundStyle(AppPalette.text)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 520)
        .sheet(isPresented: $showingTools) { NavigationStack { ToolDirectoryView() } }
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.compact) {
            Image(systemName: icon)
                .appTextRole(.control)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .appTextRole(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppPalette.text)
                Text(subtitle)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(AppSpacing.row)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One delivered-tool list reused by Home, Train and Maia. Selecting a row only opens it.
struct ToolDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var onOpen: ((Route) -> Void)?
    @State private var search = ""

    private func tools(in category: AppToolCategory) -> [AppToolDescriptor] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppToolCatalog.tools(in: category).filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) ||
                $0.detail.localizedCaseInsensitiveContains(query) || category.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if AppToolCategory.allCases.allSatisfy({ tools(in: $0).isEmpty }) {
                    ContentUnavailableView.search(text: search)
                }
                ForEach(AppToolCategory.allCases.filter { !tools(in: $0).isEmpty }) { category in
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text(category.rawValue).appTextRole(.sectionTitle)
                        VStack(spacing: 0) {
                            ForEach(tools(in: category)) { tool in
                                Button { open(tool.route) } label: {
                                    HStack(alignment: .center, spacing: AppSpacing.row) {
                                        if !dynamicTypeSize.isAccessibilitySize {
                                            Image(systemName: tool.systemImage)
                                                .appFont(size: 20, weight: .medium)
                                                .frame(width: 28).accessibilityHidden(true)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(tool.title).appTextRole(.body)
                                            Text(tool.detail).appTextRole(.secondary).foregroundStyle(.secondary)
                                        }
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        if !dynamicTypeSize.isAccessibilitySize {
                                            Image(systemName: "chevron.right").appFont(size: 12, weight: .semibold).accessibilityHidden(true)
                                        }
                                    }
                                    .foregroundStyle(AppPalette.text)
                                    .padding(AppSpacing.row)
                                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityHint("Opens \(tool.title)")
                                .accessibilityIdentifier("tool_\(tool.id)")
                                if tool.id != tools(in: category).last?.id { Divider().padding(.leading, 52) }
                            }
                        }
                        .appSurface(.quiet, padding: 0)
                    }
                }
            }
            .padding(AppSpacing.screenHorizontal)
        }
        .background(AppPalette.canvas)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a tool")
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPresented {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .accessibilityIdentifier("tool_directory")
    }

    private func open(_ route: Route) {
        dismiss()
        if let onOpen { onOpen(route) } else { AppCoordinator.shared.navigate(to: route) }
    }
}
