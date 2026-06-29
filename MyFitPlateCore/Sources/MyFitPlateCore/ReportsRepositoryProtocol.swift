import Foundation
import Combine

public protocol ReportsRepositoryProtocol {
    func fetchMealScoreHistory(userID: String) async throws -> [DateValuePoint]
    func saveMealScore(userID: String, date: Date, score: MealScore) async throws
}
