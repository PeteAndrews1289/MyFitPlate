import SwiftUI

struct MultiArcProgressView: View {
    let progress1: Double // 0.0 to 1.0
    let progress2: Double
    let progress3: Double

    var body: some View {
        ZStack {
            ArcSegment(progress: progress1, radiusOffset: 0, color: Color(red: 219/255, green: 212/255, blue: 104/255))
            ArcSegment(progress: 0.8, radiusOffset: 0, color: Color(red: 219/255, green: 212/255, blue: 104/255).opacity(0.3))
            ArcSegment(progress: progress2, radiusOffset: 28, color: Color(red: 241/255, green: 104/255, blue: 56/255))
            ArcSegment(progress: 0.8, radiusOffset: 28, color: Color(red: 241/255, green: 104/255, blue: 56/255).opacity(0.3))
            ArcSegment(progress: progress3, radiusOffset: 56, color: Color(red: 64/255, green: 127/255, blue: 62/255))
            ArcSegment(progress: 0.8, radiusOffset: 56, color: Color(red: 64/255, green: 127/255, blue: 62/255).opacity(0.3))
        }
        .frame(width: 120, height: 120)
        .rotationEffect(.degrees(135)) // Rotate so concave part faces bottom-right
    }
}

struct ArcSegment: View {
    var progress: Double
    var radiusOffset: CGFloat
    var color: Color

    var body: some View {
        ArcShape()
            .trim(from: 0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            .frame(width: 170 - radiusOffset, height: 120 - radiusOffset)
            .animation(.easeInOut(duration: 0.5), value: progress)
    }
}

struct ArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Semicircle from 0° to 180°
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: .degrees(0),
                    endAngle: .degrees(180),
                    clockwise: false)
        return path
    }
}

