    //
    //  NutritionSummaryView.swift
    //  WatchPlate Watch App
    //
    //  Created by Omar Sabeha on 6/12/25.
    //

    import SwiftUI

    struct NutritionSummaryView: View {
        @EnvironmentObject var appDelegate: AppDelegate
//        var protProgress: Double {
//            guard appDelegate.totalProt > 0 else { return 0 }
//            return min(appDelegate.userProt / appDelegate.totalProt, 1)
//        }
//        var carbProgress: Double {
//            guard appDelegate.totalCarb > 0 else { return 0 }
//            return min(appDelegate.userCarb / appDelegate.totalCarb, 1)
//        }
//        var fatProgress: Double {
//            guard appDelegate.totalFat > 0 else { return 0 }
//            return min(appDelegate.userFat / appDelegate.totalFat, 1)
//        }
        
        func safePercentage(user: Double, total: Double) -> Double {
            guard total > 0 else { return 0 } // Avoid divide by zero
            return min((user / total) * 100, 100) // Clamp to 100%
        }

        
        var body: some View {
            Text("\(Int(appDelegate.userCal)) / \(Int(appDelegate.goalCal)) cals")
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.white)
            
            Text("Protein: \(Int(safePercentage(user: appDelegate.userProt, total: appDelegate.totalProt)))%")
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(Color(red: 219/255, green: 212/255, blue: 104/255))

            Text("Carbs: \(Int(safePercentage(user: appDelegate.userCarb, total: appDelegate.totalCarb)))%")
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(Color(red: 241/255, green: 104/255, blue: 56/255))

            Text("Fats: \(Int(safePercentage(user: appDelegate.userFat, total: appDelegate.totalFat)))%")
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(Color(red: 51/255, green: 149/255, blue: 81/255))

                
            let protProgress = (appDelegate.userProt / appDelegate.totalProt) * 0.8
            let carbProgress = (appDelegate.userCarb / appDelegate.totalCarb) * 0.8
            let fatProgress = (appDelegate.userFat / appDelegate.totalFat) * 0.8 
            
            GeometryReader { geometry in
                MultiArcProgressView(progress1: protProgress, progress2: carbProgress, progress3: fatProgress)
                    .frame(width: 160, height: 160)
                    .position(x: geometry.size.width - 20,
                              y: geometry.size.height - 40)
            }
            //            VStack(){
            //                Spacer()
            //                ZStack{
            //                    //            Text("Nutrition Progress")
            //                    ProgressView(value: progress)
            //                        .progressViewStyle(.circular)
            //                        .scaleEffect(3)
            //                        .tint(.pink)
            //                    ProgressView(value: progress)
            //                        .progressViewStyle(.circular)
            //                        .scaleEffect(2.4)
            //                        .tint(.green)
            //                    ProgressView(value: progress)
            //                        .progressViewStyle(.circular)
            //                        .scaleEffect(1.92)
            //                        .tint(.blue)
            //                }
            //
            //                HStack(){
            //                    Text("Protein")
            //                        .foregroundColor(.pink)
            //                        .font(.system(size: 15))
            //                    Text("Carbs")
            //                        .foregroundColor(.green)
            //                        .font(.system(size: 15))
            //                    Text("Fats")
            //                        .foregroundColor(.blue)
            //                        .font(.system(size: 15))
            //                }
            //                .padding(.top, 55)
            //
            //            }
            }
        }

//    #Preview {
//        NutritionSummaryView(appDelegate: AppDelegate())
//    }

