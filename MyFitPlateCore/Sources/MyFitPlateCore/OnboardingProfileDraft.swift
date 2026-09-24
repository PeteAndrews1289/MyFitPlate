import Foundation

/// Answers from the onboarding quiz, captured before an account exists.
///
/// Values use the app's canonical storage units (pounds and centimeters) so the draft can be
/// applied to `GoalSettings` after sign-up without reinterpreting the display-unit preference.
public struct OnboardingProfileDraft: Codable, Equatable, Sendable {
    public enum Goal: String, Codable, CaseIterable, Sendable {
        case lose = "Lose"
        case maintain = "Maintain"
        case gain = "Gain"
    }

    public var goal: Goal
    public var trainingIntent: String
    /// The sex used by the Mifflin-St Jeor estimate ("Male" or "Female").
    public var sex: String
    public var age: Int
    public var heightCm: Double
    public var currentWeightLbs: Double
    public var targetWeightLbs: Double
    public var activityMultiplier: Double
    public var reminderStyle: String
    public var maiaTone: String
    public var createdAt: Date

    public init(
        goal: Goal,
        trainingIntent: String = "General Fitness",
        sex: String,
        age: Int,
        heightCm: Double,
        currentWeightLbs: Double,
        targetWeightLbs: Double,
        activityMultiplier: Double,
        reminderStyle: String = "Gentle",
        maiaTone: String = "Balanced",
        createdAt: Date = Date()
    ) {
        self.goal = goal
        self.trainingIntent = trainingIntent
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.currentWeightLbs = currentWeightLbs
        self.targetWeightLbs = targetWeightLbs
        self.activityMultiplier = activityMultiplier
        self.reminderStyle = reminderStyle
        self.maiaTone = maiaTone
        self.createdAt = createdAt
    }

    public var isComplete: Bool {
        OnboardingProfileRules.validationIssue(for: self) == nil
    }
}

public enum OnboardingProfileRules {
    /// The energy formula is not meant for children, and MyFitPlate does not set calorie targets
    /// for anyone under 13.
    public static let ageRange = 13...100
    public static let heightRangeCm: ClosedRange<Double> = 100...250
    public static let weightRangeLbs: ClosedRange<Double> = 60...700
    /// A target closer than this to the current weight is treated as already reached.
    public static let meaningfulWeightChangeLbs = 1.0

    public enum Issue: Equatable, Sendable {
        case age
        case height
        case currentWeight
        case targetWeight
        case targetDirection(OnboardingProfileDraft.Goal)
    }

    public static func isValidAge(_ age: Int) -> Bool {
        ageRange.contains(age)
    }

    public static func isValidHeight(cm: Double) -> Bool {
        heightRangeCm.contains(cm)
    }

    public static func isValidWeight(lbs: Double) -> Bool {
        weightRangeLbs.contains(lbs)
    }

    /// A lose goal needs a lower target and a gain goal a higher one; otherwise the calorie
    /// direction and the target would pull against each other.
    public static func targetMatchesGoal(
        _ goal: OnboardingProfileDraft.Goal,
        currentWeightLbs: Double,
        targetWeightLbs: Double
    ) -> Bool {
        switch goal {
        case .lose:
            return targetWeightLbs < currentWeightLbs
        case .gain:
            return targetWeightLbs > currentWeightLbs
        case .maintain:
            return true
        }
    }

    public static func validationIssue(for draft: OnboardingProfileDraft) -> Issue? {
        if !isValidAge(draft.age) { return .age }
        if !isValidHeight(cm: draft.heightCm) { return .height }
        if !isValidWeight(lbs: draft.currentWeightLbs) { return .currentWeight }
        if !isValidWeight(lbs: draft.targetWeightLbs) { return .targetWeight }
        if !targetMatchesGoal(
            draft.goal,
            currentWeightLbs: draft.currentWeightLbs,
            targetWeightLbs: draft.targetWeightLbs
        ) {
            return .targetDirection(draft.goal)
        }
        return nil
    }
}

/// The targets shown on the plan reveal. They come from the same rules `GoalSettings` uses when
/// the draft is saved, so the numbers a person accepts are the numbers their account starts with.
public struct OnboardingPlan: Equatable, Sendable {
    public enum Projection: Equatable, Sendable {
        /// Estimated date the target weight is reached at the planned pace.
        case reachTarget(date: Date, weeks: Int)
        /// Long journeys get a nearer milestone instead of a date years away.
        case milestone(date: Date, weeks: Int, changeLbs: Double)
        case maintain
        case atTarget
        /// The minimum calorie floor leaves no reliable pace toward the target.
        case noEstimate
    }

    public let dailyCalories: Double
    public let proteinGrams: Double
    public let carbsGrams: Double
    public let fatGrams: Double
    public let maintenanceCalories: Double
    /// Planned weekly weight change in pounds; negative while losing.
    public let weeklyChangeLbs: Double
    public let isMinimumCalorieFloorApplied: Bool
    public let projection: Projection
}

public enum OnboardingPlanRules {
    public static let caloriesPerPound = 3500.0
    public static let milestoneWeeks = 12
    public static let longestProjectedWeeks = 78
    /// New accounts start from the default `GoalSettings` split.
    public static let proteinPercentage = 30.0
    public static let carbsPercentage = 50.0
    public static let fatsPercentage = 20.0

    public static func plan(
        for draft: OnboardingProfileDraft,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> OnboardingPlan {
        let bmr = GoalSettingsRules.calculateBMR(
            age: draft.age,
            weightKg: draft.currentWeightLbs / BodyUnits.lbsPerKg,
            heightCm: draft.heightCm,
            gender: draft.sex
        )
        let maintenance = bmr * draft.activityMultiplier
        let calories = GoalSettingsRules.calculateCalorieGoal(
            bmr: bmr,
            goal: draft.goal.rawValue,
            gender: draft.sex,
            calorieGoalMethod: .mifflinWithActivity,
            activityLevel: draft.activityMultiplier,
            adaptiveTDEE: nil,
            manualCaloriesBurned: 0,
            currentCalories: nil
        )
        let macros = GoalSettingsRules.updateMacros(
            calories: calories,
            proteinPercentage: proteinPercentage,
            carbsPercentage: carbsPercentage,
            fatsPercentage: fatsPercentage
        )
        let weeklyChange = (calories - maintenance) * 7 / caloriesPerPound

        return OnboardingPlan(
            dailyCalories: calories,
            proteinGrams: macros.protein,
            carbsGrams: macros.carbs,
            fatGrams: macros.fats,
            maintenanceCalories: maintenance,
            weeklyChangeLbs: weeklyChange,
            isMinimumCalorieFloorApplied: calories > maintenance + intendedAdjustment(for: draft.goal) + 0.5,
            projection: projection(for: draft, weeklyChangeLbs: weeklyChange, today: today, calendar: calendar)
        )
    }

    private static func intendedAdjustment(for goal: OnboardingProfileDraft.Goal) -> Double {
        switch goal {
        case .lose: return -250
        case .gain: return 250
        case .maintain: return 0
        }
    }

    private static func projection(
        for draft: OnboardingProfileDraft,
        weeklyChangeLbs: Double,
        today: Date,
        calendar: Calendar
    ) -> OnboardingPlan.Projection {
        guard draft.goal != .maintain else { return .maintain }

        let remaining = draft.targetWeightLbs - draft.currentWeightLbs
        guard abs(remaining) >= OnboardingProfileRules.meaningfulWeightChangeLbs else { return .atTarget }
        guard abs(weeklyChangeLbs) >= 0.05, (remaining < 0) == (weeklyChangeLbs < 0) else { return .noEstimate }

        let weeks = Int((abs(remaining) / abs(weeklyChangeLbs)).rounded(.up))
        if weeks <= longestProjectedWeeks,
           let date = calendar.date(byAdding: .day, value: weeks * 7, to: today) {
            return .reachTarget(date: date, weeks: weeks)
        }

        guard let milestoneDate = calendar.date(byAdding: .day, value: milestoneWeeks * 7, to: today) else {
            return .noEstimate
        }
        return .milestone(
            date: milestoneDate,
            weeks: milestoneWeeks,
            changeLbs: weeklyChangeLbs * Double(milestoneWeeks)
        )
    }
}
