import SwiftUI
import MapKit
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
                self.runs = runs
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
}

struct RunHistoryView: View {
    @StateObject private var viewModel = RunHistoryViewModel()
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var showingRecorder = false

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
        .onAppear { viewModel.load() }
        .fullScreenCover(isPresented: $showingRecorder, onDismiss: { viewModel.load() }) {
            RunRecorderView()
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

    private let importer = RunImportService()

    func load(run: Run, metric: Bool) {
        splits = run.splits
        averageHeartRate = run.averageHeartRate

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
