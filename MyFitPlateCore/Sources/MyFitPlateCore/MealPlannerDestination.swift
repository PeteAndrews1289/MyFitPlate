import Foundation

/// An explicit navigation request. A normal tab return may restore its last position;
/// an action from another screen must keep its own account, day and meal instead.
public struct MealPlannerDestination: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let userID: String
    public let date: Date
    public let mealID: String?
    public let mealFingerprint: String?
    public let createdAt: Date
    public let coachingReview: CoachingActionReview?
    private let originalDayKey: String?

    public init(userID: String, date: Date, meal: PlannedMeal? = nil,
                coachingReview: CoachingActionReview? = nil, now: Date = Date()) {
        id = UUID()
        self.userID = userID
        self.date = date
        mealID = meal?.id
        mealFingerprint = meal.flatMap { try? PlanFingerprint.make($0) }
        createdAt = now
        self.coachingReview = coachingReview
        originalDayKey = DiaryDayContext.dayKey(for: date)
    }

    public func isAvailable(to currentUserID: String?, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              currentUserID == userID, originalDayKey != nil,
              originalDayKey == DiaryDayContext.dayKey(for: date), age >= -1 && age <= 30 * 60 else { return false }
        if let coachingReview {
            guard coachingReview.day.userID == userID,
                  coachingReview.day.dayKey == originalDayKey,
                  (try? coachingReview.validate(userID: currentUserID, now: now,
                    currentTargetID: mealID, currentFingerprint: mealFingerprint)) != nil else { return false }
        }
        return true
    }

    public func reviewedMeal(in day: MealPlanDay?, currentUserID: String?, now: Date = Date(),
                             calendar: Calendar = .current) throws -> PlannedMeal? {
        guard isAvailable(to: currentUserID, now: now) else { throw MealPlannerDestinationError.expired }
        guard let mealID else { return nil }
        guard let day, calendar.isDate(day.date, inSameDayAs: date),
              let meal = day.meals.first(where: { $0.id == mealID }) else {
            throw MealPlannerDestinationError.missing
        }
        guard let mealFingerprint, try PlanFingerprint.make(meal) == mealFingerprint else {
            throw MealPlannerDestinationError.changed
        }
        return meal
    }
}

public enum MealPlannerDestinationError: LocalizedError {
    case expired, missing, changed

    public var errorDescription: String? {
        switch self {
        case .expired: return "This meal shortcut is no longer current. Open the meal again."
        case .missing: return "This meal is no longer on that day. Review the current plan below."
        case .changed: return "This meal changed since the suggestion was shown. Review the current plan below."
        }
    }
}
