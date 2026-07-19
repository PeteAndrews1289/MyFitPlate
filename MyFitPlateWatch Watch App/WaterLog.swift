import SwiftUI
import WatchKit

struct WaterLog: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Define proportions
        let width = rect.width
        let height = rect.height
        let neckHeight = height * 0.1
        let neckWidth = width * 0.3
        let capHeight = neckHeight
        let bodyCornerRadius = width * 0.24
        let transitionRadius = width * 0.1

        // Start at bottom center
        path.move(to: CGPoint(x: width / 2, y: height))

        // Bottom right curve
        path.addArc(center: CGPoint(x: width * 0.75, y: height - bodyCornerRadius),
                    radius: bodyCornerRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(0),
                    clockwise: true)

        // Right body up
        path.addLine(to: CGPoint(x: width * 0.89 + transitionRadius, y: neckHeight + capHeight + transitionRadius))

        // Right body-to-neck curve
        path.addArc(center: CGPoint(x: width * 0.89, y: neckHeight + capHeight + transitionRadius),
                    radius: transitionRadius,
                    startAngle: .degrees(0),
                    endAngle: .degrees(-50),
                    clockwise: true)

        // Right neck in
        path.addLine(to: CGPoint(x: width / 2 + neckWidth / 2, y: capHeight))

        // Cap right curve
        let capCornerRadius = neckWidth * 0.2
        path.addArc(center: CGPoint(x: width / 2 + neckWidth / 2 - capCornerRadius, y: capCornerRadius),
                    radius: capCornerRadius,
                    startAngle: .degrees(0),
                    endAngle: .degrees(-90),
                    clockwise: true)

        // Top straight across
        path.addLine(to: CGPoint(x: width / 2 - neckWidth / 2 + capCornerRadius, y: 0))

        // Cap left curve
        path.addArc(center: CGPoint(x: width / 2 - neckWidth / 2 + capCornerRadius, y: capCornerRadius),
                    radius: capCornerRadius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-180),
                    clockwise: true)

        // Left neck out
        path.addLine(to: CGPoint(x: width / 2 - neckWidth / 2, y: capHeight))

        // Left neck to body transition
        path.addLine(to: CGPoint(x: width * 0.08, y: neckHeight + capHeight))

        // Left body-to-neck curve (mirror of right)
        path.addArc(center: CGPoint(x: width * 0.12, y: neckHeight + capHeight + transitionRadius),
                    radius: transitionRadius,
                    startAngle: .degrees(-140),
                    endAngle: .degrees(-170),
                    clockwise: true)

        // Left body down
        path.addLine(to: CGPoint(x: width * 0.25 - bodyCornerRadius, y: height - bodyCornerRadius))

        // Bottom left curve
        path.addArc(center: CGPoint(x: width * 0.25, y: height - bodyCornerRadius),
                    radius: bodyCornerRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(90),
                    clockwise: true)

        // Close path
        path.closeSubpath()

        return path
    }
}

// Crown builds up a pending amount (shown as the lighter band); Log commits it.
// The commit updates the watch optimistically and queues the ounces for the phone,
// which logs them for real and pushes the trued-up total back as context.
struct WaterBottleView: View {
    @EnvironmentObject var appDelegate: AppDelegate

    @State private var pendingOunces: Double = 0

    private var goal: Double { max(appDelegate.goalWater, 1) }
    private var loggedFraction: CGFloat { CGFloat(min(appDelegate.currWater / goal, 1.0)) }
    private var pendingFraction: CGFloat { CGFloat(min((appDelegate.currWater + pendingOunces) / goal, 1.0)) }

    var body: some View {
        GeometryReader { geometry in
            let minSide = min(geometry.size.width, geometry.size.height)
            let bottleWidth = minSide * 0.52
            let bottleHeight = minSide * 0.92

            VStack(spacing: 6) {
                ZStack {
                    WaterLog()
                        .stroke(Color.white.opacity(0.85), lineWidth: max(minSide * 0.012, 1))
                        .frame(width: bottleWidth, height: bottleHeight)

                    // Pending band (lighter) sits under the logged fill so the
                    // crown's not-yet-committed water reads as "about to be added".
                    fillRect(fraction: pendingFraction, width: bottleWidth, height: bottleHeight)
                        .foregroundStyle(WatchPalette.accentWater.opacity(0.45))

                    fillRect(fraction: loggedFraction, width: bottleWidth, height: bottleHeight)
                        .foregroundStyle(WatchPalette.accentWater)
                }
                .focusable(true)
                .digitalCrownRotation(
                    $pendingOunces,
                    from: 0,
                    through: 40,
                    by: 2,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Water")
                .accessibilityValue("\(Int(appDelegate.currWater)) of \(Int(goal)) ounces")

                Text("\(Int(appDelegate.currWater)) / \(Int(goal)) oz")
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.numericText())

                if pendingOunces > 0 {
                    Button {
                        let amount = pendingOunces
                        pendingOunces = 0
                        appDelegate.logWater(ounces: amount)
                        WKInterfaceDevice.current().play(.success)
                    } label: {
                        Text("Log \(Int(pendingOunces)) oz")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.black.opacity(0.86))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(WatchPalette.brandPrimary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Turn the crown to add water")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .navigationTitle("Water")
    }

    private func fillRect(fraction: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .frame(width: width, height: height * fraction)
            .offset(y: height * (1 - fraction) / 2)
            .mask(WaterLog().frame(width: width, height: height))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: fraction)
    }
}

#Preview {
    WaterBottleView()
        .environmentObject(AppDelegate())
}
