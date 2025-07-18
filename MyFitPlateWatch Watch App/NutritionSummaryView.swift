import SwiftUI

struct NutritionSummaryView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    
    func safePercentage(user: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min((user / total) * 100, 100)
    }
    
    private func calculateProgress(consumed: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(consumed / goal, 1.0) * 0.8
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
        
        let protProgress = calculateProgress(consumed: appDelegate.userProt, goal: appDelegate.totalProt)
        let carbProgress = calculateProgress(consumed: appDelegate.userCarb, goal: appDelegate.totalCarb)
        let fatProgress = calculateProgress(consumed: appDelegate.userFat, goal: appDelegate.totalFat)
        
        GeometryReader { geometry in
            MultiArcProgressView(progress1: protProgress, progress2: carbProgress, progress3: fatProgress)
                .frame(width: 160, height: 160)
                .position(x: geometry.size.width - 20,
                          y: geometry.size.height - 40)
        }
    }
}
