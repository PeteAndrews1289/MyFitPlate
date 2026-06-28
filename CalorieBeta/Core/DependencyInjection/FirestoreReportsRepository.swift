import Foundation
import FirebaseFirestore
import Combine

class FirestoreReportsRepository: ReportsRepositoryProtocol {
    private let db = Firestore.firestore()
    
    func fetchMealScoreHistory(userID: String) async throws -> [DateValuePoint] {
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailySummaries).order(by: "date", descending: true).limit(to: 30).getDocuments()
        
        return snapshot.documents.compactMap { doc -> DateValuePoint? in
            guard let timestamp = doc.data()["date"] as? Timestamp, let scoreValue = doc.data()["mealOverallScore"] as? Double else {
                if let timestamp = doc.data()["date"] as? Timestamp, let scoreString = doc.data()["mealScore"] as? String {
                    let fallbackScoreValue: Double
                    switch scoreString { case "A+": fallbackScoreValue = 95; case "A-": fallbackScoreValue = 85; case "B": fallbackScoreValue = 75; case "C": fallbackScoreValue = 65; case "D": fallbackScoreValue = 55; default: fallbackScoreValue = 0 }
                    return DateValuePoint(date: timestamp.dateValue(), value: fallbackScoreValue)
                }
                return nil
            }
            return DateValuePoint(date: timestamp.dateValue(), value: scoreValue)
        }
    }
    
    func saveMealScore(userID: String, date: Date, score: MealScore) async throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailySummaries).document(dateString)
        let data: [String: Any] = [
            "date": Timestamp(date: date),
            "mealScore": score.grade,
            "mealOverallScore": score.overallScore,
            "calorieScore": score.calorieScore,
            "macroScore": score.macroScore,
            "qualityScore": score.qualityScore,
            "totalCalories": score.actualCalories,
            "totalProtein": score.actualProtein,
            "totalCarbs": score.actualCarbs,
            "totalFats": score.actualFats
        ]
        try await ref.setData(data, merge: true)
    }
}
