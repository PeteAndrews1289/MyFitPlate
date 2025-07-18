
import SwiftUI

struct AudioVisualizerView: View {
    @State private var barHeights: [CGFloat] = [20, 35, 25, 40, 30]
    
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barHeights.count, id: \.self) { index in
                Capsule()
                    .fill(Color.brandPrimary)
                    .frame(width: 6, height: barHeights[index])
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                for i in 0..<barHeights.count {
                    barHeights[i] = CGFloat.random(in: 10...40)
                }
            }
        }
    }
}
