import SwiftUI
import MapKit
import MyFitPlateCore

struct RunStoryPosterView: View {
    let run: Run
    let routeCoordinates: [CLLocationCoordinate2D]
    let useMetric: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: Image?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                posterContent
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                    .scaleEffect(0.85)
                    .frame(maxHeight: 520)

                if let renderedImage {
                    ShareLink(
                        item: renderedImage,
                        subject: Text("MyFitPlate Run Story"),
                        message: Text(MyFitPlateLinks.shareMessage("My latest run, fueled and tracked with MyFitPlate.")),
                        preview: SharePreview("MyFitPlate Run Story", image: renderedImage)
                    ) {
                        Label("Share Story to Instagram / Messages", systemImage: "square.and.arrow.up")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(AppPalette.onBrand)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        DIContainer.shared.analyticsManager?.logEvent("run_story_share_opened", parameters: nil)
                    })
                    .padding(.horizontal)
                } else {
                    ProgressView("Preparing Story Image...")
                        .padding()
                }
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Share Run Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                renderImage()
            }
        }
    }

    private func renderImage() {
        // Render asynchronously after view layout settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let renderer = ImageRenderer(content: posterContent.frame(width: 360, height: 640))
            renderer.scale = UIScreen.main.scale
            if let uiImage = renderer.uiImage {
                renderedImage = Image(uiImage: uiImage)
            }
        }
    }

    private var posterContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("MYFITPLATE", systemImage: "bolt.heart.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.brandPrimary)
                Spacer()
                Text(run.startDate.formatted(date: .abbreviated, time: .omitted))
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.white.opacity(0.7))
            }

            if !routeCoordinates.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 280)

                    RouteTraceShape(coordinates: routeCoordinates)
                        .stroke(
                            Gradient(colors: [.yellow, .green, .brandPrimary, .cyan]),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                        )
                        .padding(24)
                        .frame(height: 280)
                }
            } else {
                Spacer()
                Image(systemName: "figure.run")
                    .font(.system(size: 80))
                    .foregroundColor(.brandPrimary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(RunFormat.distanceText(meters: run.distanceMeters, metric: useMetric))
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 20) {
                    if let pace = RunFormat.paceText(secondsPerKm: run.averagePaceSecondsPerKm, metric: useMetric) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AVG PACE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                            Text(pace)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TIME")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Text(RunFormat.durationText(seconds: run.movingSeconds))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    if let cals = run.activeCalories {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BURN")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                            Text("\(Int(cals.rounded())) cal")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Text("Fueled & Tracked with MyFitPlate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Image(systemName: "flame.fill")
                    .foregroundColor(.yellow)
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

private struct RouteTraceShape: Shape {
    let coordinates: [CLLocationCoordinate2D]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard coordinates.count > 1 else { return path }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max(),
              maxLat > minLat, maxLon > minLon else { return path }

        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon

        for (i, coord) in coordinates.enumerated() {
            let x = CGFloat((coord.longitude - minLon) / lonRange) * (rect.width - 10) + 5
            let y = CGFloat(1.0 - (coord.latitude - minLat) / latRange) * (rect.height - 10) + 5
            let pt = CGPoint(x: x, y: y)
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        return path
    }
}
