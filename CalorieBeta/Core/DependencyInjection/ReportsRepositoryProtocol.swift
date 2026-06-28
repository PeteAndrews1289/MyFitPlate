import Foundation
import Combine

protocol ReportsRepositoryProtocol {
    func fetchMealScoreHistory(userID: String) async throws -> [DateValuePoint]
    func saveMealScore(userID: String, date: Date, score: MealScore) async throws
}
