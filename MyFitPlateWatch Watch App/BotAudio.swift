////
////  BotAudio.swift
////  WatchPlate Watch App
////
////  Created by Omar Sabeha on 6/12/25.
////
//
//import SwiftUI
//
//struct BotAudio: View {
//    @State private var barHeights: [CGFloat] = [30, 50, 40, 60]
//    @State private var isAnimating = false
//    
//    let barWidth: CGFloat = 8
//    let spacing: CGFloat = 6
//    let baseHeight: CGFloat = 20
//    
//    var body: some View {
//        HStack(spacing: spacing) {
//            ForEach(0..<4) { index in
//                Capsule()
//                    .fill(Color.white)
//                    .frame(width: barWidth, height: barHeights[index])
//            }
//        }
//        .onAppear {
//            startBouncing()
//        }
//    }
//    
//    func startBouncing() {
//        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
//            withAnimation(.easeInOut(duration: 0.2)) {
//                for i in 0..<barHeights.count {
//                    barHeights[i] = CGFloat.random(in: 20...60)
//                }
//            }
//        }
//    }
//}
//
//#Preview {
//    ZStack {
//        Color.black.ignoresSafeArea()
//        BotAudio()
//    }
//}
