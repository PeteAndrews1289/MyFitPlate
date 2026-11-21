import SwiftUI
import MapKit
import UniformTypeIdentifiers
import MyFitPlateCore

struct RunStoryPosterView: View {
    let run: Run
    let routeSegments: [[CLLocationCoordinate2D]]
    private var projectedSegments: [[CLLocationCoordinate2D]] {
        RunRouteShareProjection.segments(routeSegments.map { segment in
            segment.map { RunShareCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        }, hidingEndpointMeters: Double(options.hiddenMeters), showRoute: options.showRoute)
        .map { $0.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
    }
    let useMetric: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: Image?
    @State private var options = RunStoryOptions()
    @State private var renderRequest = UUID()
    @State private var renderFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.section) {
                    if let renderedImage {
                        renderedImage.resizable().scaledToFit().frame(maxWidth: 300)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.surface))
                            .accessibilityLabel("Exact story image preview")
                            .accessibilityIdentifier("run_story_preview")
                    } else if renderFailed {
                        ContentUnavailableView("Image unavailable", systemImage: "photo", description: Text("Your choices are kept. Try preparing the image again."))
                        Button("Retry image") { renderImage() }.buttonStyle(AppActionButtonStyle(.secondary))
                    } else {
                        ProgressView("Preparing story…").frame(height: 280)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(title: "Share your way", subtitle: "These choices affect this shared image only.")
                        Picker("Layout", selection: $options.layout) {
                            ForEach(RunStoryLayout.allCases) { layout in Text(layout.rawValue).tag(layout) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("run_story_layout")
                        Toggle("Show route", isOn: $options.showRoute)
                            .disabled(routeSegments.isEmpty || options.layout != .route)
                            .accessibilityIdentifier("run_story_show_route")
                        if options.layout == .route && options.showRoute && !routeSegments.isEmpty {
                            Picker("Hide start and finish", selection: $options.hiddenMeters) {
                                Text("No crop").tag(0)
                                Text("200 m").tag(200)
                                Text("500 m").tag(500)
                                Text("1 km").tag(1000)
                            }
                            .accessibilityIdentifier("run_story_privacy")
                            Text(options.hiddenMeters > 0
                                ? "Coordinates within \(options.hiddenMeters) m of either endpoint are hidden, including any later visits. Short routes may be hidden completely."
                                : "The route shape includes its original start and finish. Review the image before sharing.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("Distance", isOn: $options.showDistance)
                        Toggle("Active time", isOn: $options.showTime)
                        Toggle("Average pace", isOn: $options.showPace)
                        Toggle("Calories", isOn: $options.showCalories)
                        Toggle("Date", isOn: $options.showDate)
                    }.appTextRole(.control).appSurface(.quiet)

                    if let renderedImage {
                        ShareLink(item: renderedImage, subject: Text("MyFitPlate Run Story"),
                            message: Text(MyFitPlateLinks.shareMessage("My latest run, fueled and tracked with MyFitPlate.")),
                            preview: SharePreview("MyFitPlate Run Story", image: renderedImage)) {
                            Label("Share story image", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .accessibilityIdentifier("run_story_share")
                        .simultaneousGesture(TapGesture().onEnded {
                            DIContainer.shared.analyticsManager?.logEvent("run_story_share_opened", parameters: nil)
                        })
                    }
                }.padding(AppSpacing.screenHorizontal)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Run story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } } }
            .onAppear { renderImage() }
            .onChange(of: options) { _, _ in renderImage() }
        }
    }

    private func renderImage() {
        let request = UUID()
        renderRequest = request
        renderedImage = nil
        renderFailed = false
        let projection = posterContent.frame(width: 360, height: 640)
        DispatchQueue.main.async {
            guard request == renderRequest else { return }
            let renderer = ImageRenderer(content: projection)
            renderer.scale = 3
            guard let uiImage = renderer.uiImage else { renderFailed = true; return }
            renderedImage = Image(uiImage: uiImage)
        }
    }

    private var posterContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("MYFITPLATE", systemImage: "bolt.heart.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.brandPrimary)
                Spacer()
                if options.showDate {
                    Text(run.startDate.formatted(date: .abbreviated, time: .omitted))
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            if options.layout == .splits {
                VStack(alignment: .leading, spacing: 12) {
                    Text("THE SPLITS").font(.system(size: 24, weight: .black)).foregroundStyle(.white)
                    if run.splits.isEmpty {
                        Text("No measured splits available").foregroundStyle(.white.opacity(0.7))
                    } else {
                        ForEach(Array(run.splits.prefix(6).enumerated()), id: \.offset) { _, split in
                            HStack {
                                Text("\(split.index)").frame(width: 20, alignment: .leading)
                                Text(RunFormat.distanceText(meters: split.distanceMeters, metric: useMetric))
                                Spacer()
                                Text(RunFormat.paceText(secondsPerKm: split.paceSecondsPerKm, metric: useMetric) ?? "—")
                            }.font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                        }
                        if run.splits.count > 6 { Text("First 6 of \(run.splits.count) splits").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) }
                    }
                }.frame(height: 250, alignment: .center)
            } else if options.layout == .route && !projectedSegments.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 280)

                    RouteTraceShape(segments: projectedSegments)
                        .stroke(
                            Gradient(colors: [AppPalette.effort, AppPalette.brand, AppPalette.recovery]),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                        )
                        .padding(24)
                        .frame(height: 280)
                }
            } else if options.layout == .route {
                Spacer()
            } else {
                Text("ONE RUN.\nYOUR PROGRESS.")
                    .font(.system(size: 45, weight: .black, design: .rounded))
                    .foregroundStyle(.white).lineSpacing(-4).padding(.vertical, 32)
                Image(systemName: "figure.run")
                    .font(.system(size: 80))
                    .foregroundColor(.brandPrimary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                if options.showDistance {
                    Text(RunFormat.distanceText(meters: run.distanceMeters, metric: useMetric))
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }

                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                    if options.showPace, let pace = RunFormat.paceText(secondsPerKm: run.averagePaceSecondsPerKm, metric: useMetric) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AVG PACE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                            Text(pace)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(AppPalette.effort)
                        }
                    }
                    if options.showTime {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ACTIVE TIME")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Text(RunFormat.durationText(seconds: run.movingSeconds))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    }
                    if options.showCalories, let cals = run.activeCalories, cals.isFinite {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CALORIES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                            Text("\(Int(cals.rounded())) cal")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(AppPalette.effort)
                        }
                    }
                }
            }

            if options.layout == .route, options.showRoute, options.hiddenMeters > 0, !projectedSegments.isEmpty {
                Text("Start and finish hidden · route gaps preserved")
                    .font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.6))
            }
            if run.isIndoor {
                Text(run.reviewAnnotation == nil ? "Indoor run" : "Indoor run · reviewed manual totals")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.7))
            }
            Spacer()

            HStack {
                Text("Fueled & Tracked with MyFitPlate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Image(systemName: "flame.fill")
                    .foregroundColor(AppPalette.effort)
            }
        }
        .padding(24)
        .frame(width: 360, height: 640)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.1, blue: 0.12), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct RunStoryOptions: Equatable {
    var layout = RunStoryLayout.route
    var showRoute = true
    var hiddenMeters = 200
    var showDistance = true
    var showTime = true
    var showPace = true
    var showCalories = false
    var showDate = true
}

private enum RunStoryLayout: String, CaseIterable, Identifiable {
    case route = "Route", statistics = "Stats", splits = "Splits"
    var id: String { rawValue }
}

private struct RouteTraceShape: Shape {
    let segments: [[CLLocationCoordinate2D]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let coordinates = segments.flatMap { $0 }
        var boundaries: Set<Int> = []
        var offset = 0
        for segment in segments { boundaries.insert(offset); offset += segment.count }
        guard coordinates.count > 1 else { return path }
        let lats = coordinates.map(\.latitude)
        let longitudeOrigin = coordinates[0].longitude
        func longitude(_ value: Double) -> Double {
            let delta = (value - longitudeOrigin).truncatingRemainder(dividingBy: 360)
            return delta > 180 ? delta - 360 : delta < -180 ? delta + 360 : delta
        }
        let lons = coordinates.map { longitude($0.longitude) }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return path }

        let longitudeScale = max(0.01, cos((minLat + maxLat) / 2 * .pi / 180))
        let horizontalSpan = (maxLon - minLon) * longitudeScale
        let verticalSpan = maxLat - minLat
        let span = max(horizontalSpan, verticalSpan, 0.000001)
        let scale = Double(min(rect.width, rect.height) - 10) / span
        let middleLatitude = (minLat + maxLat) / 2
        let middleLongitude = (minLon + maxLon) / 2

        for (i, coord) in coordinates.enumerated() {
            let x = rect.midX + CGFloat((longitude(coord.longitude) - middleLongitude) * longitudeScale * scale)
            let y = rect.midY - CGFloat((coord.latitude - middleLatitude) * scale)
            let pt = CGPoint(x: x, y: y)
            if boundaries.contains(i) {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        return path
    }
}

private struct RunSummaryCSV: Transferable {
    let content: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { value in Data(value.content.utf8) }
            .suggestedFileName("run-summary.csv")
    }
}

struct RunSummaryExportView: View {
    @Environment(\.dismiss) private var dismiss
    let run: Run
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppSectionHeader(title: "Export run summary", subtitle: "A CSV you can open in a spreadsheet.")
                Text("Includes distance in meters, active and elapsed seconds, average pace, available energy/heart-rate totals, source, and known pause/recovery timing. Unknown events stay marked unknown.")
                    .appTextRole(.secondary)
                if run.reviewAnnotation != nil {
                    Text("This summary labels the reviewed treadmill totals and also includes the original distance and active time. The private correction reason is omitted.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Label("No route coordinates, account information or Health identifiers are included.", systemImage: "location.slash")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                ShareLink(item: RunSummaryCSV(content: RunSummaryExport.csv(run: run)), preview: SharePreview("Run summary CSV")) {
                    Label("Export summary.csv", systemImage: "square.and.arrow.up")
                }.buttonStyle(AppActionButtonStyle(.primary)).accessibilityIdentifier("run_summary_export")
                Spacer()
            }.padding(AppSpacing.screenHorizontal)
                .background(AppPalette.canvas.ignoresSafeArea())
                .navigationTitle("Run data").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
