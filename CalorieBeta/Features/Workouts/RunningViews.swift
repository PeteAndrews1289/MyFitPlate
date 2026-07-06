import SwiftUI
import MapKit
import Charts
import MyFitPlateCore

// Running history + detail. Runs come straight from HealthKit (any watch whose app
// syncs to Apple Health), filtered and de-duplicated by RunImportRules — HealthKit is
// the single source of truth, so there's nothing to sync and nothing to drift.

@MainActor
final class RunHistoryViewModel: ObservableObject {
    @Published var runs: [Run] = []
    @Published var isLoading = true

    private let importer = RunImportService()

    func load() {
        HealthKitManager.shared.requestAuthorization { [weak self] _, _ in
            guard let self else { return }
            let since = Calendar.current.date(byAdding: .day, value: -180, to: Date()) ?? Date()
            self.importer.fetchRuns(since: since) { runs in
                self.runs = RunningShoeStore().applyTags(to: runs)
                self.isLoading = false
            }
        }
    }

    var thisWeekMeters: Double {
        runs.filter { Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .weekOfYear) }
            .reduce(0) { $0 + $1.distanceMeters }
    }

    var thisWeekCount: Int {
        runs.filter { Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .weekOfYear) }.count
    }

    var records: RunStats.PersonalRecords {
        RunStats.personalRecords(from: runs)
    }
}

struct RunHistoryView: View {
    @StateObject private var viewModel = RunHistoryViewModel()
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var showingRecorder = false
    @State private var showingGearManager = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    showingRecorder = true
                } label: {
                    Label("Start run", systemImage: "figure.run")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                if !viewModel.runs.isEmpty {
                    weekHero
                    RunRecordsCard(records: viewModel.records, metric: useMetric)
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.runs) { run in
                            NavigationLink(destination: RunDetailView(run: run)) {
                                RunRow(run: run, metric: useMetric)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Running")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        HapticManager.instance.feedback(.light)
                        showingGearManager = true
                    } label: {
                        Image(systemName: "shoeprints.fill")
                            .foregroundColor(.brandPrimary)
                    }
                    .accessibilityLabel("Shoe Gear Manager")

                    NavigationLink(destination: RunMapView(runs: viewModel.runs)) {
                        Image(systemName: "map")
                            .foregroundColor(.brandPrimary)
                    }
                    .accessibilityLabel("Route map")
                }
            }
        }
        .onAppear { viewModel.load() }
        .fullScreenCover(isPresented: $showingRecorder, onDismiss: { viewModel.load() }) {
            RunRecorderView()
        }
        .sheet(isPresented: $showingGearManager, onDismiss: { viewModel.load() }) {
            ShoeGearManagerView(runs: viewModel.runs)
        }
    }

    // DESIGN.md rule 1: the question is "how is my running week going?"
    private var weekHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This week")
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(RunFormat.distanceText(meters: viewModel.thisWeekMeters, metric: useMetric))
                    .appFont(size: 28, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .contentTransition(.numericText())
                Text(viewModel.thisWeekCount == 1 ? "1 run" : "\(viewModel.thisWeekCount) runs")
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .asCard()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🏃")
                .font(.system(size: 42))
                .accessibilityHidden(true)
            Text("No runs yet")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)
            Text("Record one right here with Start run, or finish a run on any watch that syncs to Apple Health — Apple Watch, Garmin, Polar, Coros — and it shows up automatically.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct RunRow: View {
    let run: Run
    let metric: Bool

    private var subtitle: String {
        var parts = [RunFormat.distanceText(meters: run.distanceMeters, metric: metric)]
        if let pace = RunFormat.paceText(secondsPerKm: run.averagePaceSecondsPerKm, metric: metric) {
            parts.append(pace)
        }
        parts.append(RunFormat.durationText(seconds: run.movingSeconds))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(run.isIndoor ? "🏃‍♂️" : "🏃")
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Text(run.source.displayName)
                .appFont(size: 10, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(UIColor.secondarySystemFill), in: Capsule())
        }
        .asCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

@MainActor
final class RunDetailViewModel: ObservableObject {
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var splits: [RunSplit] = []
    @Published var averageHeartRate: Double?
    @Published var isLoadingRoute = true
    @Published var ghostPaceComparison: RunStats.GhostPaceComparison?

    private let importer = RunImportService()

    func load(run: Run, metric: Bool) {
        splits = run.splits
        averageHeartRate = run.averageHeartRate

        let since = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        importer.fetchRuns(since: since) { [weak self] history in
            self?.ghostPaceComparison = RunStats.ghostPaceComparison(for: run, against: history)
        }

        importer.fetchRoute(forRunID: run.id) { [weak self] fixes in
            guard let self else { return }
            self.routeCoordinates = fixes.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            // Imports carry no splits — replay the GPS trace through the same engine the
            // live recorder uses, so a Garmin run gets real per-km splits anyway.
            if self.splits.isEmpty, fixes.count > 1 {
                let replay = RunSession(metric: metric)
                replay.start(at: fixes[0].timestamp)
                fixes.forEach { replay.ingest($0) }
                if let replayed = replay.finish(at: fixes[fixes.count - 1].timestamp) {
                    self.splits = replayed.splits
                }
            }
            self.isLoadingRoute = false
        }

        if run.averageHeartRate == nil {
            importer.fetchAverageHeartRate(start: run.startDate, end: run.endDate) { [weak self] bpm in
                self?.averageHeartRate = bpm
            }
        }
    }
}

struct RunDetailView: View {
    let run: Run
    @StateObject private var viewModel = RunDetailViewModel()
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !viewModel.routeCoordinates.isEmpty {
                    routeMap
                } else if run.isIndoor {
                    Text("Indoor run")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(UIColor.secondarySystemFill), in: Capsule())
                }

                statsGrid

                if !viewModel.splits.isEmpty {
                    splitsCard
                }

                if let comparison = viewModel.ghostPaceComparison {
                    ghostPaceCard(comparison)
                }

                shoeTagCard
                
                Text("Recorded with \(run.source.displayName)")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(run.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load(run: run, metric: useMetric) }
    }

    private var shoeTagCard: some View {
        let store = RunningShoeStore()
        let currentShoe = store.shoeID(forRunID: run.id).flatMap { store.shoe(for: $0) } ?? store.defaultShoe()
        return HStack {
            Image(systemName: "shoeprints.fill")
                .foregroundColor(.accentProtein)
                .font(.system(size: 20))
                .frame(width: 38, height: 38)
                .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Gear Tagged")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(currentShoe.map { "\($0.brand) · \($0.name)" } ?? "Select Shoe")
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.textPrimary)
            }

            Spacer()

            Menu {
                ForEach(store.shoes.filter { !$0.isRetired }) { shoe in
                    Button {
                        HapticManager.instance.feedback(.light)
                        store.tagRun(runID: run.id, withShoeID: shoe.id)
                    } label: {
                        HStack {
                            Text("\(shoe.brand) · \(shoe.name)")
                            if currentShoe?.id == shoe.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("Change")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.brandPrimary.opacity(0.12), in: Capsule())
            }
        }
        .asCard()
    }

    private func ghostPaceCard(_ comparison: RunStats.GhostPaceComparison) -> some View {
        HStack(spacing: 14) {
            Image(systemName: comparison.isPR ? "trophy.fill" : "ghost.fill")
                .foregroundColor(comparison.isPR ? .yellow : .brandPrimary)
                .font(.system(size: 22))
                .frame(width: 42, height: 42)
                .background(
                    (comparison.isPR ? Color.yellow : Color.brandPrimary).opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comparison.isPR ? "🏆 New Route PR!" : "Ghost Pace Loop")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)

                    if !comparison.isPR {
                        Text("vs \(comparison.matchingRunsCount) similar runs")
                            .appFont(size: 11, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }

                let diffText = RunFormat.paceDiffText(secondsPerKmDiff: comparison.paceDifferenceVsAverage, metric: useMetric)
                Text("\(diffText) vs average on this loop")
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(comparison.paceDifferenceVsAverage < 0 ? .green : .textPrimary)
            }

            Spacer()

            if let prPace = RunFormat.paceText(secondsPerKm: comparison.prPaceSecondsPerKm, metric: useMetric) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Loop Best")
                        .appFont(size: 10, weight: .bold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    Text(prPace)
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .monospacedDigit()
                }
            }
        }
        .asCard()
    }

    private var routeMap: some View {
        Map(interactionModes: []) {
            MapPolyline(coordinates: viewModel.routeCoordinates)
                .stroke(Color.brandPrimary, lineWidth: 4)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Route map of this run")
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            RunStatTile(label: "Distance", value: RunFormat.distanceText(meters: run.distanceMeters, metric: useMetric))
            RunStatTile(label: "Time", value: RunFormat.durationText(seconds: run.movingSeconds))
            if let pace = RunFormat.paceText(secondsPerKm: run.averagePaceSecondsPerKm, metric: useMetric) {
                RunStatTile(label: "Avg pace", value: pace)
            }
            if let bpm = viewModel.averageHeartRate {
                RunStatTile(label: "Avg heart rate", value: "\(Int(bpm.rounded())) bpm")
            }
            if let calories = run.activeCalories {
                RunStatTile(label: "Calories", value: "\(Int(calories.rounded()).formatted()) cal")
            }
        }
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Splits")
                .appFont(size: 14, weight: .bold)
                .foregroundColor(.textPrimary)

            ForEach(viewModel.splits, id: \.index) { split in
                HStack {
                    Text("\(split.index)")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 24, alignment: .leading)
                    Text(split.distanceMeters + 1 < (useMetric ? 1000 : RunFormat.metersPerMile)
                         ? RunFormat.distanceText(meters: split.distanceMeters, metric: useMetric)
                         : (useMetric ? "1 km" : "1 mi"))
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Spacer()
                    Text(RunFormat.paceText(secondsPerKm: split.paceSecondsPerKm, metric: useMetric) ?? RunFormat.durationText(seconds: split.seconds))
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                }
            }
        }
        .asCard()
    }
}

private struct RunStatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .appFont(size: 11, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .asCard()
    }
}

// MARK: - Records

struct RunRecordsCard: View {
    let records: RunStats.PersonalRecords
    let metric: Bool

    private var hasAnything: Bool {
        records.longestRun != nil || records.best5KSeconds != nil || records.best10KSeconds != nil
    }

    var body: some View {
        if hasAnything {
            VStack(alignment: .leading, spacing: 8) {
                Text("Records")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)

                if let longest = records.longestRun {
                    recordRow("Longest run", RunFormat.distanceText(meters: longest.distanceMeters, metric: metric))
                }
                if let best5K = records.best5KSeconds {
                    recordRow("Best 5K", RunFormat.durationText(seconds: best5K))
                }
                if let best10K = records.best10KSeconds {
                    recordRow("Best 10K", RunFormat.durationText(seconds: best10K))
                }

                Text("5K and 10K times are estimated from each run's average pace.")
                    .appFont(size: 10)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .asCard()
        }
    }

    private func recordRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text("🏅")
                .font(.system(size: 14))
                .accessibilityHidden(true)
            Text(label)
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Spacer()
            Text(value)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(.textPrimary)
                .monospacedDigit()
        }
    }
}

// MARK: - All-routes map

/// Every recent outdoor route on one map — the Strava-wall feel. Routes are decimated
/// (RouteSimplify, tested) and capped so thirty runs render as smoothly as three; the
/// latest run draws at full strength, history fades behind it.
struct RunMapView: View {
    let runs: [Run]

    private struct LoadedRoute {
        let id: String
        let coordinates: [CLLocationCoordinate2D]
        let isLatest: Bool
    }

    @State private var routes: [LoadedRoute] = []
    @State private var isLoading = true
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    private static let maxRoutes = 30

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(routes, id: \.id) { route in
                MapPolyline(coordinates: route.coordinates)
                    .stroke(
                        route.isLatest ? Color.brandPrimary : Color.brandPrimary.opacity(0.35),
                        lineWidth: route.isLatest ? 4 : 3
                    )
            }
        }
        .overlay(alignment: .bottom) {
            Group {
                if isLoading {
                    Label("Drawing your routes", systemImage: "map")
                        .appFont(size: 12, weight: .semibold)
                } else if routes.isEmpty {
                    Text("No routes yet — outdoor runs draw themselves here.")
                        .appFont(size: 12, weight: .semibold)
                } else {
                    Text(routes.count == 1 ? "Your latest route" : "Your last \(routes.count) routes")
                        .appFont(size: 12, weight: .semibold)
                }
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 12)
        }
        .navigationTitle("Route map")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRoutes() }
    }

    @MainActor
    private func loadRoutes() async {
        guard routes.isEmpty else { return }
        let importer = RunImportService()
        let candidates = runs.filter { !$0.isIndoor }.prefix(Self.maxRoutes)

        for (index, run) in candidates.enumerated() {
            let fixes = await withCheckedContinuation { (continuation: CheckedContinuation<[RunLocationFix], Never>) in
                importer.fetchRoute(forRunID: run.id) { continuation.resume(returning: $0) }
            }
            guard fixes.count > 1 else { continue }
            let coordinates = RouteSimplify.decimate(fixes, maxPoints: 200).map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            routes.append(LoadedRoute(id: run.id, coordinates: coordinates, isLatest: index == 0))
        }
        isLoading = false
    }
}

// MARK: - Reports card

/// Weekly mileage over the last 8 weeks, shown in Reports only when there's any running
/// at all — non-runners never see an empty chart.
struct RunMileageCard: View {
    @State private var weeks: [RunStats.WeekMileage] = []
    @State private var loaded = false
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    private var totalMeters: Double { weeks.reduce(0) { $0 + $1.meters } }

    var body: some View {
        Group {
            if loaded && totalMeters > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Running")
                            .appFont(size: 14, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("Last 8 weeks · \(RunFormat.distanceText(meters: totalMeters, metric: useMetric))")
                            .appFont(size: 11)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }

                    Chart(weeks, id: \.weekStart) { week in
                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Distance", useMetric ? week.meters / 1000 : week.meters / RunFormat.metersPerMile)
                        )
                        .foregroundStyle(Color.brandPrimary)
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                                .font(.system(size: 9))
                        }
                    }
                    .frame(height: 110)
                    .accessibilityLabel("Weekly running distance, last 8 weeks")
                }
                .asCard()
            }
        }
        .onAppear {
            guard !loaded else { return }
            let since = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? Date()
            RunImportService().fetchRuns(since: since) { runs in
                weeks = RunStats.weeklyMileage(runs: runs, weeks: 8)
                loaded = true
            }
        }
    }
}
