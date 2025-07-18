import SwiftUI

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

struct WaterBottleView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var fillLevel: CGFloat = 0.3  // 0.0 to 1.0
    @State private var lastFillLevel: CGFloat = 0.3
    @State private var showingSheet = false
    
    var body: some View {
        GeometryReader { geometry in
            let minSide = min(geometry.size.width, geometry.size.height)
            let bottleWidth = minSide * 0.5
            let bottleHeight = minSide * 1.0
            ScrollView {
                VStack(spacing: 10){
                    ZStack {
                        // Bottle Outline
                        WaterLog()
                            .stroke(Color.white, lineWidth: minSide * 0.01)
                            .frame(width: bottleWidth, height: bottleHeight)
                        
                        // Fill shape masked by the bottle
                        Rectangle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.cyan, .blue.opacity(0.7)]),
                                startPoint: .bottom, endPoint: .top ))
                            .frame(width: bottleWidth, height: bottleHeight * fillLevel)
                            .offset(y: bottleHeight * (1 - fillLevel) / 2)
                            .mask(
                                WaterLog()
                                    .frame(width: bottleWidth, height: bottleHeight)
                            )
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .focusable(true)
                    .digitalCrownRotation(
                        Binding(
                            get: { fillLevel },
                            set: { newValue in
                                if newValue > fillLevel { // Only allow increase
                                    fillLevel = min(newValue, 1.0) // Clamp to 1.0
                                    appDelegate.currWater = Double(fillLevel) * appDelegate.goalWater
                                    lastFillLevel = fillLevel
                                }
                            }
                        ),
                        from: 0.0,
                        through: 1.0,
                        by: 0.01,
                        sensitivity: .low,
                        isContinuous: true,
                        isHapticFeedbackEnabled: true
                    )
                    
                    
                    ZStack{
                        //                    Rectangle()
                        //                        .fill(Color.gray.opacity(0.6))
                        //                        .cornerRadius(20)
                        //                        .frame(width: 90)
                        
                        Text("\(Int(appDelegate.currWater)) / \(Int(appDelegate.goalWater)) oz")
                            .font(.headline)
                        //                        .foregroundColor(.whiteverbatim: String)
                        
                    }
                    
                    Button("Edit Goal") {
                        showingSheet = true
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .buttonStyle(.plain)
                }
                
            }
        }
        .sheet(isPresented: $showingSheet) {
            editWaterGoal()
        }
        
        
        .padding()
    }
}

struct editWaterGoal: View {
    @EnvironmentObject var appDelegate: AppDelegate
    var body: some View {
        VStack{
            Text("\(appDelegate.goalWater) oz")
                .digitalCrownRotation(
                            Binding(
                                get: { appDelegate.goalWater },
                                set: { newValue in
                                    // Clamp to a sensible range
                                    appDelegate.goalWater = min(max(newValue, 8), 256) // min 8oz, max 256oz
                                }
                            ),
                            from: 0,        // Minimum goal
                            through: 256,   // Maximum goal
                            by: 8,          // Increment in ounces
                            sensitivity: .low,
                            isContinuous: true,
                            isHapticFeedbackEnabled: true
                        )
        }
       
    }
}


#Preview {
    WaterBottleView()
}
