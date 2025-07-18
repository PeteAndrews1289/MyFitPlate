//
//  WeightTracker.swift
//  WatchPlate Watch App
//
//  Created by Omar Sabeha on 6/13/25.
//

import SwiftUI

struct WeightTracker: View {
    @EnvironmentObject var appDelegate: AppDelegate
    
    var body: some View {
        VStack (spacing: 50) {

            ZStack {
                ProgressView(value: 0.3)
                    .progressViewStyle(.circular)
                    .scaleEffect(3)
                    .tint(.green)
                    .padding(.top,20)
                
                Text("\(Int(appDelegate.userWeight))")
                    .padding(.top,20)
            }
            
            Text("Goal: \(Int(appDelegate.goalWeight)) lbs")
                .padding(.top, 20)
        }
        
        
            
    }
}
//
//#Preview {
//    WeightTracker()
//        
//}
