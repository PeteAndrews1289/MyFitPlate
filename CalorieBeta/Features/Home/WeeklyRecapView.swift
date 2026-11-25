import SwiftUI
import MyFitPlateCore

struct WeeklyRecapView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var goalSettings: GoalSettings
    @EnvironmentObject private var workoutService: WorkoutService
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    @StateObject private var loader: WeeklyRecapLoader
    @State private var csvURL: URL?
    @State private var didRecordView = false
    @State private var showingShareOptions = false
    @State private var reportFocus: WeeklyReportFocus = .overview
    @State private var selectedWeekEnding = Date()
    @State private var intentionText = ""
    @State private var pinnedIntention: WeeklyRecapIntention?
    @State private var previousIntention: WeeklyRecapIntention?
    @State private var preservedRevisions: [WeeklyRecapRevision] = []
    @State private var journalMessage: String?
    @FocusState private var editingIntention: Bool

    init(initialRecap: WeeklyRecap? = nil) {
        _loader = StateObject(wrappedValue: WeeklyRecapLoader(initialRecap: initialRecap))
        #if DEBUG
        if ScreenshotDemoMode.isEnabled,
           let value = ProcessInfo.processInfo.environment["MFP_TEST_REPORT_WEEK_ENDING"],
           let timestamp = TimeInterval(value), timestamp.isFinite {
            _selectedWeekEnding = State(initialValue: Date(timeIntervalSince1970: timestamp))
        }
        #endif
    }

    private var recap: WeeklyRecap? { loader.recap }
    private var isLoading: Bool { loader.isLoading }
    private var loadMessage: String? { loader.loadMessage }

    private var weightUnit: String { BodyUnits.weightUnit(metric: useMetric) }

    private var reportCalendar: Calendar {
        var calendar = Calendar.current
        if let timeZoneID = loader.revision?.window.timeZoneID, let timeZone = TimeZone(identifier: timeZoneID) { calendar.timeZone = timeZone }
        return calendar
    }

    private func displayEndingDay(_ recap: WeeklyRecap) -> Date {
        reportCalendar.date(byAdding: .day, value: 6, to: reportCalendar.startOfDay(for: recap.weekStart)) ?? recap.weekStart
    }

    private func reportDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = reportCalendar; formatter.timeZone = reportCalendar.timeZone; formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private var weekRangeText: String {
        guard let recap else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = reportCalendar; formatter.timeZone = reportCalendar.timeZone
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: recap.weekStart)) - \(formatter.string(from: displayEndingDay(recap)))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekPicker
                    if let recap {
                        reportContent(recap)
                    } else if isLoading {
                        WeeklyReportLoadingState()
                    } else {
                        WeeklyReportEmptyState(
                            message: loadMessage ?? "There is not enough data to build this report yet.",
                            retry: { Task { await loadRecap(force: true) } }
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .containerRelativeFrame(.horizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Training & Fuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if recap != nil { shareMenu }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingIntention = false }.accessibilityIdentifier("weekly_report_finish_typing")
                }
            }
            .onAppear {
                #if DEBUG
                guard ScreenshotDemoMode.isEnabled else { return }
                switch ScreenshotDemoData.requestedScreen {
                case "weekly-report-training": reportFocus = .training
                case "weekly-report-fuel": reportFocus = .fuel
                case "weekly-report-share": showingShareOptions = true
                default: break
                }
                #endif
            }
            .task(id: Calendar.current.startOfDay(for: selectedWeekEnding)) { await loadRecap() }
            .refreshable { await loadRecap(force: true) }
            .onDisappear(perform: cleanupCSVExport)
            .sheet(isPresented: $showingShareOptions) {
                if let recap {
                    WeeklyRecapShareOptionsView(
                        recap: recap,
                        weekRangeText: weekRangeText,
                        useMetric: useMetric
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private func reportContent(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            let focusPicker = Picker("Report section", selection: $reportFocus) {
                ForEach(WeeklyReportFocus.allCases) { focus in Text(focus.title).tag(focus) }
            }
            .accessibilityIdentifier("weekly_report_focus")
            if dynamicTypeSize.isAccessibilitySize {
                focusPicker.pickerStyle(.menu)
            } else {
                focusPicker.pickerStyle(.segmented)
            }

            if let loadMessage { Text(loadMessage).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
            switch reportFocus {
            case .overview:
                WeekInMotionView(recap: recap, showsDetailAction: false)
                if let revision = loader.revision {
                    comparisonCard(revision)
                    intentionCard(revision)
                }
            case .training:
                Text("Recorded work, with warmups excluded from progress totals.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                strengthCard(recap)
                runningCard(recap)
            case .fuel:
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    WeeklyReportSectionHeader(title: "Fueling", subtitle: "Coverage from the days and runs available to assess.")
                    fuelingCard(recap)
                }
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    WeeklyReportSectionHeader(title: "Context", subtitle: "Outcomes and data quality, kept separate from scores.")
                    contextCard(recap)
                }
            }
            evidenceCard
        }
    }

    private var weekPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            let week = DatePicker("Week ending", selection: $selectedWeekEnding, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact).appTextRole(.caption)
                .accessibilityIdentifier("weekly_report_week")
            if dynamicTypeSize.isAccessibilitySize {
                Text("Week ending").appTextRole(.caption)
                week.labelsHidden()
                HStack {
                    weekStepButton(forward: false)
                    Spacer()
                    weekStepButton(forward: true)
                }
            } else {
                HStack(spacing: 12) {
                    weekStepButton(forward: false)
                    week
                    weekStepButton(forward: true)
                }
            }
        }
        .tint(.textPrimary)
    }

    private func weekStepButton(forward: Bool) -> some View {
        Button { shiftWeek(forward ? 1 : -1) } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left").frame(width: 44, height: 44)
        }
        .disabled(forward && Calendar.current.isDateInToday(selectedWeekEnding))
        .accessibilityLabel(forward ? "Next week" : "Previous week")
        .accessibilityIdentifier(forward ? "weekly_report_next" : "weekly_report_previous")
    }

    private func shiftWeek(_ direction: Int) {
        selectedWeekEnding = min(Date(), Calendar.current.date(byAdding: .day, value: direction * 7,
                                                               to: selectedWeekEnding) ?? selectedWeekEnding)
    }

    private func comparisonCard(_ revision: WeeklyRecapRevision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compared with the previous 7 days").appTextRole(.control)
            Text(reportDateLabel(revision.prior.weekStart) + " – " +
                 reportDateLabel(displayEndingDay(revision.prior)))
                .appTextRole(.caption).foregroundStyle(.secondary)
            if revision.prior.hasAnyActivity {
                WeeklyReportDetailRow(icon: "dumbbell", title: "Strength sessions",
                    value: "\(revision.prior.workoutsCompleted) → \(revision.recap.workoutsCompleted)",
                    detail: "Saved sessions in each window; this does not infer missed workouts.")
                WeeklyReportDetailRow(icon: "fork.knife", title: "Days with food recorded",
                    value: "\(revision.prior.daysLogged) → \(revision.recap.daysLogged)",
                    detail: "Partial days are included here, but excluded from average intake.")
                if let before = revision.prior.averageCalories, let after = revision.recap.averageCalories {
                    Text("Average on complete diary days: \(Int(before.rounded()).formatted()) → \(Int(after.rounded()).formatted()) cal/day. Different numbers of complete days can affect this comparison.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                } else {
                    Text("An intake comparison needs complete diary days in both weeks. Missing entries are not low intake.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No earlier recorded activity is available in this window. A percentage change would imply a baseline we do not have.")
                    .appTextRole(.body).foregroundStyle(.secondary)
            }
        }.weeklyReportSurface().accessibilityElement(children: .contain)
            .accessibilityIdentifier("weekly_report_comparison")
            .accessibilityValue("Week ending " + reportDateLabel(displayEndingDay(revision.recap)))
    }

    private func intentionCard(_ revision: WeeklyRecapRevision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let previousIntention {
                Text("Your intention for this week").appTextRole(.control)
                Text(previousIntention.text).appTextRole(.body)
                Menu {
                    ForEach(WeeklyRecapIntention.Outcome.allCases, id: \.rawValue) { outcome in
                        Button(outcome.title) {
                            do {
                                self.previousIntention = try WeeklyRecapJournal().reflect(on: previousIntention,
                                    outcome: outcome, currentUserID: DIContainer.shared.authService.currentUserID)
                                journalMessage = "Reflection saved on this device."
                            } catch { journalMessage = error.localizedDescription }
                        }
                    }
                } label: {
                    Label(previousIntention.outcome?.title ?? "Reflect on intention", systemImage: "checkmark.bubble")
                }.buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("weekly_report_reflect")
                Divider()
            }
            Text("One intention for next week").appTextRole(.control)
            TextField("What would make the next week better?", text: $intentionText, axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.roundedBorder).focused($editingIntention)
                .accessibilityIdentifier("weekly_report_intention")
            Button(pinnedIntention == nil ? "Pin intention" : "Update intention") {
                do {
                    pinnedIntention = try WeeklyRecapJournal().pin(text: intentionText, from: revision,
                        currentUserID: DIContainer.shared.authService.currentUserID)
                    journalMessage = "Pinned for the following 7 days on this device."
                } catch { journalMessage = error.localizedDescription }
            }.buttonStyle(AppActionButtonStyle(.secondary))
                .disabled(intentionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || intentionText.count > 180)
                .accessibilityIdentifier("weekly_report_pin")
            Text("A personal intention, not a target change. Review how it went in the following week's report.")
                .appTextRole(.caption).foregroundStyle(.secondary)
            if let journalMessage { Text(journalMessage).appTextRole(.caption).accessibilityIdentifier("weekly_report_journal_status") }
        }.weeklyReportSurface()
    }

    private var evidenceCard: some View {
        DisclosureGroup(loader.wasUpdated ? "Updated evidence & saved versions" : "Evidence & saved versions") {
            VStack(alignment: .leading, spacing: 10) {
                if let coverage = loader.coverageMessage { Text(coverage).appTextRole(.caption) }
                if let revision = loader.revision {
                    Text("Checked \(revision.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(revision.window.timeZoneID)")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    Text("Refresh includes late imports and corrections. Prepared share versions stay on this device.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    ForEach(preservedRevisions.filter { $0.id != revision.id && $0.preparedForSharingAt != nil }) { saved in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Prepared \(saved.preparedForSharingAt?.formatted(date: .abbreviated, time: .shortened) ?? "earlier")")
                                .appTextRole(.body)
                            Text("\(saved.recap.workoutsCompleted) strength sessions · \(saved.recap.runCount) runs · \(saved.recap.daysLogged) days with food recorded")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                            ShareLink(item: WeeklyRecapCSVExporter.csvString(for: saved.recap, metric: useMetric,
                                revisionID: saved.id, timeZoneID: saved.window.timeZoneID)) {
                                Label("Share saved data", systemImage: "square.and.arrow.up")
                            }.appTextRole(.caption)
                        }
                    }
                }
                Button("Refresh evidence") { Task { await loadRecap(force: true) } }
                    .frame(minHeight: 44)
                    .disabled(isLoading).accessibilityIdentifier("weekly_report_refresh")
            }.padding(.top, 8)
        }.appTextRole(.body).weeklyReportSurface()
            .accessibilityElement(children: .contain).accessibilityIdentifier("weekly_report_evidence")
    }

    private func refreshJournal() {
        guard let revision = loader.revision, revision.ownerID == DIContainer.shared.authService.currentUserID else {
            pinnedIntention = nil; previousIntention = nil; preservedRevisions = []; intentionText = ""; return
        }
        do {
            let journal = WeeklyRecapJournal(), calendar = Calendar.current
            preservedRevisions = try journal.revisions(ownerID: revision.ownerID, window: revision.window)
            previousIntention = try journal.intention(ownerID: revision.ownerID, targetWindow: revision.window)
            let next = WeeklyRecapWindow(endingOn: calendar.date(byAdding: .day, value: 7, to: revision.window.lastDay) ?? revision.window.lastDay, calendar: calendar)
            pinnedIntention = try journal.intention(ownerID: revision.ownerID, targetWindow: next)
            intentionText = pinnedIntention?.text ?? ""; journalMessage = nil
        } catch { journalMessage = error.localizedDescription }
    }

    private func retainShareRevision() {
        guard let revision = loader.revision else { return }
        do {
            try WeeklyRecapJournal().prepareForSharing(revision,
                currentUserID: DIContainer.shared.authService.currentUserID)
            preservedRevisions = try WeeklyRecapJournal().revisions(ownerID: revision.ownerID, window: revision.window)
        } catch { journalMessage = error.localizedDescription }
    }

    private func strengthCard(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WeeklyReportCardHeader(
                title: "Strength",
                subtitle: recap.workoutsCompleted == 0
                    ? "No strength sessions recorded"
                    : "\(recap.workoutsCompleted) \(recap.workoutsCompleted == 1 ? "session" : "sessions")",
                icon: "dumbbell.fill"
            )

            if recap.workoutsCompleted > 0 {
                WeeklyMetricLayout(metrics: [
                    WeeklyMetricValue(title: "Working sets", value: recap.workingSetCount.formatted()),
                    WeeklyMetricValue(title: useMetric ? "Volume · kg-reps" : "Volume · lb-reps", value: volumeText(recap.totalVolume)),
                    WeeklyMetricValue(title: "PRs", value: recap.personalRecords.formatted())
                ])

                Divider()

                WeeklyReportDetailRow(
                    icon: "gauge.with.dots.needle.50percent",
                    title: "Effort",
                    value: effortText(recap),
                    detail: effortDetail(recap)
                )

                WeeklyReportDetailRow(
                    icon: "flame",
                    title: "Hard days",
                    value: recap.demandingStrengthDays.formatted(),
                    detail: "8+ working sets or average RPE 8+"
                )

                if recap.personalRecords > 0 {
                    WeeklyReportCallout(
                        icon: "star.fill",
                        text: "\(recap.personalRecords) \(recap.personalRecords == 1 ? "lift beat" : "lifts beat") prior history.",
                        color: .accentPositive
                    )
                }
            }
        }
        .weeklyReportSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly_report_strength")
    }

    private func runningCard(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WeeklyReportCardHeader(
                title: "Running",
                subtitle: recap.runCount == 0
                    ? "No runs recorded"
                    : "\(recap.runCount) \(recap.runCount == 1 ? "run" : "runs")",
                icon: "figure.run"
            )

            if recap.runCount > 0 {
                WeeklyMetricLayout(metrics: [
                    WeeklyMetricValue(title: "Distance", value: RunFormat.distanceText(meters: recap.runMeters, metric: useMetric)),
                    WeeklyMetricValue(title: "Time", value: RunFormat.durationText(seconds: recap.runMovingSeconds)),
                    WeeklyMetricValue(
                        title: "Avg pace",
                        value: RunFormat.paceText(secondsPerKm: recap.averageRunPaceSecondsPerKm, metric: useMetric) ?? "Not available"
                    )
                ])

                Divider()

                WeeklyReportDetailRow(
                    icon: "arrow.left.arrow.right",
                    title: "Prior 7 days",
                    value: runChangeText(recap),
                    detail: recap.priorRunMeters > 0
                        ? "Previously \(RunFormat.distanceText(meters: recap.priorRunMeters, metric: useMetric))"
                        : "No prior-week mileage baseline"
                )

                WeeklyReportDetailRow(
                    icon: "medal.fill",
                    title: "Records",
                    value: recap.runRecordCount.formatted(),
                    detail: recap.paceRecordCount == 0
                        ? "No similar-distance pace bests"
                        : "\(recap.paceRecordCount) similar-distance pace \(recap.paceRecordCount == 1 ? "best" : "bests")"
                )

                WeeklyReportDetailRow(
                    icon: "map.fill",
                    title: "Routes",
                    value: recap.outdoorRunCount > 0
                        ? "\(recap.routeRunCount) of \(recap.outdoorRunCount)"
                        : "Not applicable",
                    detail: recap.outdoorRunCount > 0 ? "Outdoor runs with a confirmed route" : "Indoor runs do not require a route"
                )

                if recap.guidedRunCount > 0 {
                    WeeklyReportDetailRow(
                        icon: "list.number",
                        title: "Guided runs",
                        value: recap.guidedRunCount.formatted(),
                        detail: "\(recap.guidedCompletedSteps) of \(recap.guidedRecordedSteps) recorded steps completed"
                    )
                }

                if let zones = recap.heartRateZoneSeconds {
                    Divider()
                    heartRateZones(zones)
                }

                if let shoe = recap.shoeContext {
                    Divider()
                    shoeRow(shoe)
                }
            }
        }
        .weeklyReportSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly_report_running")
    }

    private func fuelingCard(_ recap: WeeklyRecap) -> some View {
        let trainingCoverage = WeeklyRecapProgress(
            completed: recap.trainingDaysLogged,
            eligible: recap.trainingDays
        )

        return VStack(alignment: .leading, spacing: 16) {
            WeeklyReportProgressRow(
                title: "Diary coverage",
                progress: WeeklyRecapProgress(completed: recap.daysLogged, eligible: 7),
                detail: "Days with at least one food logged",
                color: .brandPrimary
            )

            WeeklyReportProgressRow(
                title: "Training-day coverage",
                progress: trainingCoverage,
                detail: recap.trainingDays == 0 ? "No training days to assess" : "Training days with food in the diary",
                color: .accentPositive
            )

            WeeklyReportProgressRow(
                title: "Calories",
                progress: recap.calorieAdherence,
                detail: calorieDetail(recap),
                color: AppPalette.energy
            )

            WeeklyReportProgressRow(
                title: "Protein",
                progress: recap.proteinAdherence,
                detail: proteinDetail(recap),
                color: .accentProtein
            )

            WeeklyReportProgressRow(
                title: "Hard-day fuel",
                progress: recap.demandingStrengthFuelAdherence,
                detail: hardDayFuelDetail(recap),
                color: .accentCarbs
            )

            WeeklyReportProgressRow(
                title: "Run recovery",
                progress: recap.recoveryFuelAdherence,
                detail: recoveryDetail(recap),
                color: .accentPositive
            )
        }
        .weeklyReportSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly_report_fueling")
    }

    private func contextCard(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WeeklyReportDetailRow(
                icon: "chart.line.flattrend.xyaxis",
                title: "Smoothed weight",
                value: smoothedWeightText(recap),
                detail: recap.smoothedWeightChange == nil
                    ? "At least two weigh-ins or a prior baseline are needed"
                    : "Exponential moving average, alpha 0.4"
            )

            Divider()

            WeeklyReportProgressRow(
                title: "Trust review",
                progress: recap.trustReview,
                detail: recap.trustReview.eligible == 0
                    ? "No logged foods required review"
                    : "Review-required food entries confirmed or corrected",
                color: .accentPositive
            )
        }
        .weeklyReportSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly_report_context")
    }

    private func heartRateZones(_ seconds: [Double]) -> some View {
        let total = seconds.reduce(0, +)
        let colors: [Color] = [.gray, .blue, .accentPositive, .orange, .red]

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Heart-rate zones")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(RunFormat.durationText(seconds: total))
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .monospacedDigit()
            }

            ForEach(Array(seconds.enumerated()), id: \.offset) { index, zoneSeconds in
                HStack(spacing: 10) {
                    Text("Z\(index + 1)")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(colors[index])
                        .frame(width: 24, alignment: .leading)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(UIColor.tertiarySystemFill))
                            Capsule()
                                .fill(colors[index])
                                .frame(width: geometry.size.width * (total > 0 ? zoneSeconds / total : 0))
                        }
                    }
                    .frame(height: 7)

                    Text(RunFormat.durationText(seconds: zoneSeconds))
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zone \(index + 1), \(RunFormat.durationText(seconds: zoneSeconds))")
            }
        }
    }

    private func shoeRow(_ shoe: WeeklyRecapShoeContext) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WeeklyReportDetailRow(
                icon: "shoeprints.fill",
                title: shoe.name,
                value: "\(Int((shoe.wearFraction * 100).rounded()).formatted())%",
                detail: shoe.isWornOut
                    ? "Replacement distance reached"
                    : "\(RunFormat.distanceText(meters: shoe.totalMeters, metric: useMetric)) tracked"
            )

            ProgressView(value: min(max(shoe.wearFraction, 0), 1))
                .tint(shoe.isWornOut ? AppPalette.caution : .brandPrimary)
                .accessibilityLabel("Shoe wear")
                .accessibilityValue("\(Int((shoe.wearFraction * 100).rounded())) percent")
        }
    }

    @ViewBuilder
    private var shareMenu: some View {
        Menu {
            Button {
                retainShareRevision()
                showingShareOptions = true
            } label: {
                Label("Choose summary image", systemImage: "photo")
            }

            if let csvURL {
                ShareLink(
                    item: csvURL,
                    subject: Text("Training & Fuel · " + weekRangeText),
                    message: Text("Aggregate weekly data from MyFitPlate. Routes, food names, account details, and raw heart-rate samples are not included.")
                ) {
                    Label("Share data as CSV", systemImage: "tablecells")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share report")
        .simultaneousGesture(TapGesture().onEnded {
            retainShareRevision()
            DIContainer.shared.analyticsManager?.logEvent(
                ProductAnalytics.Event.weeklyReportShareOpened.rawValue,
                parameters: nil
            )
        })
        .accessibilityIdentifier("weekly_report_share")
    }

    @MainActor
    private func loadRecap(force: Bool = false) async {
        await loader.load(
            dailyLogService: dailyLogService,
            workoutService: workoutService,
            goalSettings: goalSettings,
            weekEnding: selectedWeekEnding,
            force: force
        )
        guard let built = loader.recap else { return }

        if !didRecordView {
            didRecordView = true
            DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.weeklyRecapViewed.rawValue, parameters: [
                "days_logged": built.daysLogged,
                "training_days": built.trainingDays,
                "workouts": built.workoutsCompleted,
                "runs": built.runCount,
                "prs": built.personalRecords + built.runRecordCount
            ])
        }
        prepareCSV(for: built)
        refreshJournal()
    }

    private func prepareCSV(for recap: WeeklyRecap) {
        cleanupCSVExport()
        let formatter = DateFormatter()
        formatter.calendar = reportCalendar; formatter.timeZone = reportCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "MyFitPlate-Training-Fuel-\(formatter.string(from: recap.weekStart))-to-\(formatter.string(from: displayEndingDay(recap))).csv"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyFitPlateWeeklyExport-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent(filename)
        let csv = WeeklyRecapCSVExporter.csvString(for: recap, metric: useMetric,
            revisionID: loader.revision?.id, timeZoneID: loader.revision?.window.timeZoneID ?? TimeZone.current.identifier)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try Data(csv.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            csvURL = url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            csvURL = nil
            AppLog.data.error("Weekly report CSV could not be prepared: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cleanupCSVExport() {
        guard let csvURL else { return }
        self.csvURL = nil
        try? FileManager.default.removeItem(at: csvURL.deletingLastPathComponent())
    }

    private func volumeText(_ poundsReps: Double) -> String {
        guard poundsReps > 0 else { return "0" }
        let displayed = BodyUnits.weightDisplayValue(lbs: poundsReps, metric: useMetric)
        return Int(displayed.rounded()).formatted()
    }

    private func effortText(_ recap: WeeklyRecap) -> String {
        guard let effort = recap.averageEffortRPE else { return "Not logged" }
        return String(format: "%.1f RPE", effort)
    }

    private func effortDetail(_ recap: WeeklyRecap) -> String {
        guard let change = recap.effortChange else { return "No comparable prior-week effort" }
        if abs(change) < 0.05 { return "Level with the prior 7 days" }
        return String(format: "%+.1f vs the prior 7 days", change)
    }

    private func runChangeText(_ recap: WeeklyRecap) -> String {
        guard let change = recap.runDistanceChangeFraction else {
            return recap.runMeters > 0 ? "New baseline" : "Not available"
        }
        return String(format: "%+.0f%%", change * 100)
    }

    private func calorieDetail(_ recap: WeeklyRecap) -> String {
        guard let goal = recap.calorieGoal else {
            return recap.calorieAdherence.eligible > 0
                ? "Within 10% of the confirmed target for each eligible complete diary day"
                : "Complete diary days and confirmed targets for those dates are needed; today's target is not applied to earlier days"
        }
        let average = recap.averageCalories.map { Int($0.rounded()).formatted() } ?? "No average"
        return "\(average) cal average on fully logged days; within 10% of \(Int(goal.rounded()).formatted())"
    }

    private func proteinDetail(_ recap: WeeklyRecap) -> String {
        guard let goal = recap.proteinGoal else {
            return recap.proteinAdherence.eligible > 0
                ? "At least 90% of the confirmed target for each eligible complete diary day"
                : "No complete diary day with a confirmed historical protein target is available"
        }
        let average = recap.averageProtein.map { Int($0.rounded()).formatted() } ?? "No average"
        return "\(average) g average on fully logged days; at least 90% of \(Int(goal.rounded()).formatted()) g"
    }

    private func hardDayFuelDetail(_ recap: WeeklyRecap) -> String {
        guard recap.demandingStrengthDays > 0 else { return "No hard strength days to assess" }
        guard recap.demandingStrengthFuelAdherence.eligible > 0 else {
            return "Complete diary days and confirmed targets are needed; missing food records are not counted as missed targets"
        }
        return "Both targets logged; food was present on \(recap.demandingStrengthDaysLogged) of \(recap.demandingStrengthDays) hard days"
    }

    private func recoveryDetail(_ recap: WeeklyRecap) -> String {
        let unknown = recap.recoveryFuelUnknownRuns ?? 0
        guard recap.recoveryFuelAdherence.eligible > 0 else {
            if unknown > 0 { return "\(unknown) runs need a body-weight record from before the run; today's weight is not substituted" }
            return recap.recoveryFuelPendingRuns > 0
                ? "\(recap.recoveryFuelPendingRuns) recovery \(recap.recoveryFuelPendingRuns == 1 ? "window is" : "windows are") still open"
                : "No run required a formal recovery target"
        }
        let pending = recap.recoveryFuelPendingRuns > 0
            ? "; \(recap.recoveryFuelPendingRuns) still open"
            : ""
        return "\(recap.recoveryFuelAdherence.completed) met both targets; timed food logged after \(recap.recoveryFuelLoggedRuns) of \(recap.recoveryFuelAdherence.eligible) assessed runs\(pending)" + (unknown > 0 ? "; \(unknown) without historical weight excluded" : "")
    }

    private func smoothedWeightText(_ recap: WeeklyRecap) -> String {
        guard let change = recap.smoothedWeightChange else { return "Not available" }
        let display = BodyUnits.weightDisplayValue(lbs: change, metric: useMetric)
        return String(format: "%+.1f %@", display, weightUnit)
    }
}

private enum WeeklyReportFocus: String, CaseIterable, Identifiable {
    case overview, training, fuel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .training: return "Training"
        case .fuel: return "Fuel & health"
        }
    }
}

private struct WeeklyReportSectionHeader: View {
    let title: String
    let subtitle: String
    var body: some View { AppSectionHeader(title: title, subtitle: subtitle) }
}

private struct WeeklyReportCardHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 15, weight: .bold)
                .foregroundColor(.brandForeground)
                .frame(width: 36, height: 36)
                .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyMetricValue: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

private struct WeeklyMetricLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let metrics: [WeeklyMetricValue]

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalMetrics
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(metrics) { metric in
                        metricView(metric)
                        if metric.id != metrics.last?.id {
                            Divider().frame(height: 42)
                        }
                    }
                }

                verticalMetrics
            }
        }
    }

    private var verticalMetrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(metrics) { metric in
                metricView(metric)
            }
        }
    }

    private func metricView(_ metric: WeeklyMetricValue) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.value)
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
            Text(metric.title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyReportDetailRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.textPrimary)
                    Spacer(minLength: 8)
                    Text(value)
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                Text(detail)
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyReportProgressRow: View {
    let title: String
    let progress: WeeklyRecapProgress
    let detail: String
    let color: Color

    private var valueText: String {
        progress.eligible > 0 ? "\(progress.completed) of \(progress.eligible)" : "Not available"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer(minLength: 8)
                Text(valueText)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(progress.eligible > 0 ? color : Color(UIColor.secondaryLabel))
                    .monospacedDigit()
            }

            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .tint(color)
            }

            Text(detail)
                .appFont(size: 11)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(valueText)
    }
}

private struct WeeklyReportCallout: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(color)
            Text(text)
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyReportLoadingState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView()
                .tint(.brandPrimary)
            Text("Building your weekly story")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            Text("Checking training, nutrition, recovery, and comparable history.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 80)
    }
}

private struct WeeklyReportEmptyState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal")
                .appFont(size: 30, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text("Report unavailable")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            Text(message)
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(AppActionButtonStyle(.primary))
        }
        .padding(.top, 80)
    }
}

private extension View {
    func weeklyReportSurface() -> some View {
        self.appSurface(.quiet)
    }
}

struct WeeklyShareSelection: OptionSet, Equatable {
    let rawValue: Int

    static let rhythm = WeeklyShareSelection(rawValue: 1 << 0)
    static let evidence = WeeklyShareSelection(rawValue: 1 << 1)
    static let observation = WeeklyShareSelection(rawValue: 1 << 2)
    static let standard: WeeklyShareSelection = [.rhythm, .evidence, .observation]
}

struct WeeklyRecapShareOptionsView: View {
    let recap: WeeklyRecap
    let weekRangeText: String
    let useMetric: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var includesRhythm = true
    @State private var includesEvidence = true
    @State private var includesObservation = true
    @State private var shareImage: Image?
    @State private var renderFailed = false

    private var selection: WeeklyShareSelection {
        var selection: WeeklyShareSelection = []
        if includesRhythm { selection.insert(.rhythm) }
        if includesEvidence { selection.insert(.evidence) }
        if includesObservation { selection.insert(.observation) }
        return selection
    }

    private var selectedCount: Int {
        [includesRhythm, includesEvidence, includesObservation].filter { $0 }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Include in image")
                        .appFont(size: 20, weight: .bold)

                    VStack(spacing: 0) {
                        selectionToggle(
                            title: "Seven-day rhythm",
                            systemImage: "calendar.day.timeline.left",
                            identifier: "weeklyShareRhythmToggle",
                            isOn: $includesRhythm
                        )
                        Divider()
                        selectionToggle(
                            title: "Evidence summary",
                            systemImage: "list.bullet.rectangle",
                            identifier: "weeklyShareEvidenceToggle",
                            isOn: $includesEvidence
                        )
                        Divider()
                        selectionToggle(
                            title: "Weekly observation",
                            systemImage: "quote.bubble.fill",
                            identifier: "weeklyShareObservationToggle",
                            isOn: $includesObservation
                        )
                    }
                    .appSurface(.quiet)

                    Text("Preview")
                        .appTextRole(.control)
                    FixedShareCardPreview {
                        WeeklyRecapShareCard(
                            recap: recap,
                            weekRangeText: weekRangeText,
                            useMetric: useMetric,
                            selection: selection
                        )
                    }
                    .accessibilityHidden(true)

                }
                .padding(20)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                shareAction
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.compact)
                    .background(AppPalette.canvas)
            }
            .navigationTitle("Share my week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: selection.rawValue) {
                renderShareImage()
            }
            .onAppear {
                DIContainer.shared.analyticsManager?.logEvent(
                    ProductAnalytics.Event.weeklyReportShareOptionsOpened.rawValue,
                    parameters: nil
                )
            }
        }
    }

    @ViewBuilder
    private var shareAction: some View {
        if let shareImage {
            ShareLink(item: shareImage, subject: Text("My week · " + weekRangeText),
                message: Text(MyFitPlateLinks.shareMessage("My week · " + weekRangeText)),
                preview: SharePreview(Text(weekRangeText), image: shareImage)) {
                Label("Share my week", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .simultaneousGesture(TapGesture().onEnded(logShareOpened))
            .accessibilityIdentifier("weeklyShareCommitButton")
        } else if renderFailed {
            VStack(spacing: AppSpacing.compact) {
                Text("The share image could not be prepared.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                Button("Retry preview") { renderShareImage() }
                    .buttonStyle(AppActionButtonStyle(.primary))
            }
        } else {
            ProgressView("Preparing preview…")
                .frame(maxWidth: .infinity, minHeight: 50)
        }
    }

    private func selectionToggle(
        title: String,
        systemImage: String,
        identifier: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage)
                .appFont(size: 15, weight: .semibold)
                .foregroundStyle(Color.textPrimary)
        }
        .tint(.brandPrimary)
        .padding(.vertical, 13)
        .disabled(isOn.wrappedValue && selectedCount == 1)
        .accessibilityIdentifier(identifier)
    }

    @MainActor
    private func renderShareImage() {
        let renderer = ImageRenderer(content: WeeklyRecapShareCard(
            recap: recap,
            weekRangeText: weekRangeText,
            useMetric: useMetric,
            selection: selection
        ))
        renderer.scale = max(2, displayScale)
        shareImage = renderer.uiImage.map(Image.init(uiImage:))
        renderFailed = shareImage == nil
    }

    private func logShareOpened() {
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.weeklyReportShareImageOpened.rawValue,
            parameters: [
                "includes_rhythm": includesRhythm,
                "includes_evidence": includesEvidence,
                "includes_observation": includesObservation
            ]
        )
    }
}

/// Fixed-size, aggregate-only card rendered for social sharing.
struct WeeklyRecapShareCard: View {
    let recap: WeeklyRecap
    let weekRangeText: String
    let useMetric: Bool
    var selection: WeeklyShareSelection = .standard

    private var motion: WeekInMotion { WeekInMotionBuilder.build(from: recap) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("MyFitPlate")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0.00, green: 0.66, blue: 0.38))
                Spacer()
                Text(weekRangeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.48))
            }

            Text("WEEK IN MOTION")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 0.00, green: 0.66, blue: 0.38))

            if selection.contains(.rhythm) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(motion.headline)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 0) {
                        ForEach(motion.days, id: \.date) { day in
                            VStack(spacing: 5) {
                                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Color.black.opacity(0.45))
                                ZStack {
                                    Circle()
                                        .fill(shareTrainingColor(day))
                                        .frame(width: 27, height: 27)
                                    Image(systemName: shareTrainingIcon(day))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(day.hasTraining ? AppPalette.onSignal : Color.black.opacity(0.35))
                                }
                                Circle()
                                    .fill(day.nutritionLogged
                                          ? Color(red: 0.20, green: 0.48, blue: 0.78)
                                          : Color.black.opacity(0.12))
                                    .frame(width: 6, height: 6)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            if selection.contains(.evidence) {
                VStack(spacing: 8) {
                    shareRow(label: "Training", value: shareTrainingValue)
                    shareRow(
                        label: "Fuel coverage",
                        value: recap.trainingDays > 0
                            ? "\(recap.trainingDaysLogged) of \(recap.trainingDays) training days"
                            : "\(recap.daysLogged) of 7 days"
                    )
                    shareRow(
                        label: "Recovery",
                        value: recap.recoveryFuelAdherence.eligible > 0
                            ? "\(recap.recoveryFuelAdherence.completed) of \(recap.recoveryFuelAdherence.eligible) assessed runs"
                            : "No assessed window"
                    )
                    shareRow(
                        label: "Trust",
                        value: recap.trustReview.eligible > 0
                            ? "\(recap.trustReview.completed) of \(recap.trustReview.eligible) reviewed"
                            : "No review required"
                    )
                }
            }

            if selection.contains(.observation) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(motion.observation.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(shareObservationColor)
                    Text(motion.observation.text)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(shareObservationColor).frame(width: 3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 360, height: 500, alignment: .topLeading)
        .background(Color.white)
    }

    private func shareRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.black.opacity(0.52))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    private func shareTrainingIcon(_ day: WeeklyRecapDay) -> String {
        switch day.trainingKind {
        case .rest: return "minus"
        case .strength: return "dumbbell.fill"
        case .run: return "figure.run"
        case .mixed: return "figure.cross.training"
        }
    }

    private var shareTrainingValue: String {
        switch (recap.workoutsCompleted > 0, recap.runCount > 0) {
        case (true, true):
            return "\(recap.workoutsCompleted) strength · \(RunFormat.distanceText(meters: recap.runMeters, metric: useMetric))"
        case (true, false):
            return "\(recap.workoutsCompleted) strength \(recap.workoutsCompleted == 1 ? "session" : "sessions")"
        case (false, true):
            return RunFormat.distanceText(meters: recap.runMeters, metric: useMetric)
        case (false, false):
            return "No sessions or runs"
        }
    }

    private func shareTrainingColor(_ day: WeeklyRecapDay) -> Color {
        switch day.trainingKind {
        case .rest: return Color.black.opacity(0.08)
        case .strength: return Color(red: 0.00, green: 0.66, blue: 0.38)
        case .run: return Color(red: 0.05, green: 0.48, blue: 0.92)
        case .mixed: return Color(red: 0.92, green: 0.55, blue: 0.10)
        }
    }

    private var shareObservationColor: Color {
        switch motion.observation.tone {
        case .neutral: return Color.black.opacity(0.50)
        case .positive: return Color(red: 0.00, green: 0.55, blue: 0.30)
        case .attention: return Color(red: 0.95, green: 0.42, blue: 0.08)
        }
    }
}
