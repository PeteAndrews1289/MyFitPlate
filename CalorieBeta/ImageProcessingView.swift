
import SwiftUI

struct ImageProcessingView: View {
    @State private var progress = 0.0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                Text("Analyzing Your Meal...")
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.white)
                
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .brandPrimary))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                
                Text("\(Int(progress * 100))%")
                    .appFont(size: 16, weight: .semibold)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(40)
            .onReceive(timer) { _ in
                if progress < 0.92 {
                    progress += 0.03
                }
            }
        }
    }
}
