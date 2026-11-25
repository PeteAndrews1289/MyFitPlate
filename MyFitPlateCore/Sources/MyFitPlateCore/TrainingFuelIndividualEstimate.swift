import Foundation

/// New records capture optional individually reviewed inputs. A profile default is never evidence.
public struct TrainingFuelPersonalInputs: Codable, Equatable, Sendable {
    public struct BodyMass: Codable, Equatable, Sendable {
        public let kilograms: Double
        public let measurementID: String
        public let measuredAt: Date
        public let confirmedAt: Date
        public init(kilograms: Double, measurementID: String, measuredAt: Date, confirmedAt: Date) {
            self.kilograms = kilograms; self.measurementID = measurementID
            self.measuredAt = measuredAt; self.confirmedAt = confirmedAt
        }
    }
    public enum Tolerance: String, Codable, CaseIterable, Sendable {
        case noPreference, lighterFoods, practicedDuringRun
    }
    public var adultConfirmed: Bool
    public var bodyMass: BodyMass?
    public var reviewedProteinGrams: Double?
    public var lastMealAt: Date?
    public var tolerance: Tolerance
    public var duringCarbsPerHour: Double?
    public init(adultConfirmed: Bool = false, bodyMass: BodyMass? = nil, reviewedProteinGrams: Double? = nil, lastMealAt: Date? = nil,
                tolerance: Tolerance = .noPreference, duringCarbsPerHour: Double? = nil) {
        self.adultConfirmed = adultConfirmed; self.bodyMass = bodyMass; self.reviewedProteinGrams = reviewedProteinGrams; self.lastMealAt = lastMealAt
        self.tolerance = tolerance; self.duringCarbsPerHour = duringCarbsPerHour
    }
}

public struct TrainingFuelDemandPreview: Codable, Equatable, Sendable {
    public struct Range: Codable, Equatable, Sendable {
        public let lower: Double
        public let upper: Double
        public init(lower: Double, upper: Double) { self.lower = lower; self.upper = upper }
    }
    public enum Rationale: String, Codable, Hashable, Sendable {
        case dailyProteinFirst, adultConfirmationMissing, confirmedWeightReference, weightUnknown, weightUnsupported
        case oneSharedProteinAmount, mealTimingIsUnknown, recentMealReviewed, lighterFoodPreference
        case duringNotRequested, duringNeedsPracticedStrategy, duringOutsideScope, duringNeedsSeparateDayEvidence
        case duringPracticedRate, userReviewedProtein, lowerReferencePlanningChoice, unsupportedProteinChoice
    }
    public let ruleset: String
    public let inputs: TrainingFuelPersonalInputs
    public let bodyMassProteinReference: Range?
    public let commonProteinServingReference: Range
    public let requestedSessionProteinGrams: Double?
    public let appEstimatedProteinTotal: Double
    public let appEstimatedCarbTotal: Double
    public let requestedDuringCarbGrams: Double?
    public let duringHourlyReference: Range?
    public let rationale: [Rationale]
    public let sourceIDs: [String]
    public let calculatedAt: Date
    public var requiresReview: Bool {
        let blockers: Set<Rationale> = [.adultConfirmationMissing, .weightUnsupported, .unsupportedProteinChoice,
            .duringOutsideScope, .duringNeedsPracticedStrategy, .duringNeedsSeparateDayEvidence]
        return rationale.contains { blockers.contains($0) }
    }
}

public enum TrainingFuelIndividualEstimateError: LocalizedError {
    case needsReview
    public var errorDescription: String? { "Review the personal estimate inputs before saving this plan. Your previous plan is unchanged." }
}

/// Bounded estimates require personal review; references do not establish individual needs.
/// Product input bounds constrain unsupported data; they are not clinical thresholds.
public enum TrainingFuelIndividualEstimateRules {
    public static let version = "individualized-fuel-v2"
    public static let timingSource = "issn-nutrient-timing-2017"
    public static let duringSource = "ais-sports-drinks-endurance-guidance"
    public static func preview(session: TrainingFuelSession, inputs: TrainingFuelPersonalInputs,
                               now: Date = Date(), calendar: Calendar = .current) -> TrainingFuelDemandPreview {
        var reasons: [TrainingFuelDemandPreview.Rationale] = [.dailyProteinFirst, .oneSharedProteinAmount]
        var reference: TrainingFuelDemandPreview.Range?
        var chosenProtein: Double?
        if !inputs.adultConfirmed { reasons.append(.adultConfirmationMissing) }
        if let weight = inputs.bodyMass, inputs.adultConfirmed {
            if weight.kilograms.isFinite, (30...300).contains(weight.kilograms),
               !weight.measurementID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               weight.measuredAt <= weight.confirmedAt, weight.confirmedAt <= now,
               now.timeIntervalSince(weight.measuredAt) <= 30 * 24 * 60 * 60,
               now.timeIntervalSince(weight.confirmedAt) <= 24 * 60 * 60 {
                let low = 0.25 * weight.kilograms, high = 0.40 * weight.kilograms
                reference = .init(lower: low, upper: high); reasons.append(.confirmedWeightReference)
                if let requested = inputs.reviewedProteinGrams {
                    if requested.isFinite, (low...high).contains(requested) {
                        chosenProtein = requested; reasons.append(.userReviewedProtein)
                    } else { reasons.append(.unsupportedProteinChoice) }
                } else {
                    // Rounding up preserves the reference lower bound; this is a planning default, not an optimum.
                    chosenProtein = min(high, ceil(low)); reasons.append(.lowerReferencePlanningChoice)
                }
            } else { reasons.append(.weightUnsupported) }
        } else { reasons.append(.weightUnknown) }
        if let meal = inputs.lastMealAt, meal <= now, now.timeIntervalSince(meal) <= 24 * 60 * 60 {
            reasons.append(.recentMealReviewed)
        } else { reasons.append(.mealTimingIsUnknown) }
        if inputs.tolerance == .lighterFoods { reasons.append(.lighterFoodPreference) }
        var during: Double?
        var hourly: TrainingFuelDemandPreview.Range?
        if let rate = inputs.duringCarbsPerHour {
            if !inputs.adultConfirmed || session.kind != .run || !(75...150).contains(session.expectedDurationMinutes ?? 0) ||
                !rate.isFinite || !(30...60).contains(rate) {
                reasons.append(.duringOutsideScope)
            } else if inputs.tolerance != .practicedDuringRun {
                reasons.append(.duringNeedsPracticedStrategy)
            } else if let start = session.scheduledAt,
                      calendar.isDate(start, inSameDayAs: start.addingTimeInterval(Double((session.expectedDurationMinutes ?? 0) * 60))) {
                during = rate * Double(session.expectedDurationMinutes ?? 0) / 60
                hourly = .init(lower: 30, upper: 60); reasons.append(.duringPracticedRate)
            } else { reasons.append(.duringNeedsSeparateDayEvidence) }
        } else { reasons.append(.duringNotRequested) }
        let generic = TrainingFuelPlannerRules.legacyDemandValues(for: session)
        return TrainingFuelDemandPreview(ruleset: version, inputs: inputs, bodyMassProteinReference: reference,
            commonProteinServingReference: .init(lower: 20, upper: 40), requestedSessionProteinGrams: chosenProtein,
            appEstimatedProteinTotal: chosenProtein ?? generic.protein, appEstimatedCarbTotal: max(generic.carbs, during ?? 0),
            requestedDuringCarbGrams: during, duringHourlyReference: hourly, rationale: reasons,
            sourceIDs: during == nil ? [timingSource] : [timingSource, duringSource], calculatedAt: now)
    }
}

/// Remaining amounts from a previously accepted v2 demand, before the applicable day's budget.
public struct TrainingFuelRecoveryLimits: Sendable {
    public let protein: Double
    public let carbs: Double
    public init(protein: Double, carbs: Double) { self.protein = protein; self.carbs = carbs }
}
