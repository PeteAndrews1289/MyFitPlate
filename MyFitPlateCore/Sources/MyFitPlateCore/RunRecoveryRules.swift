import Foundation

public struct RunRecoveryTarget: Codable, Equatable {
    public let targetCarbGrams: Int
    public let targetProteinGrams: Int
    public let rehydrateMilliLiters: Int
    public let windowMinutes: Int
    public let runDistanceMeters: Double
    public let activeCalories: Double
    public let runID: String
    public let timestamp: Date

    public init(
        targetCarbGrams: Int,
        targetProteinGrams: Int,
        rehydrateMilliLiters: Int,
        windowMinutes: Int = 45,
        runDistanceMeters: Double,
        activeCalories: Double,
        runID: String,
        timestamp: Date = Date()
    ) {
        self.targetCarbGrams = targetCarbGrams
        self.targetProteinGrams = targetProteinGrams
        self.rehydrateMilliLiters = rehydrateMilliLiters
        self.windowMinutes = windowMinutes
        self.runDistanceMeters = runDistanceMeters
        self.activeCalories = activeCalories
        self.runID = runID
        self.timestamp = timestamp
    }

    public var isExpired: Bool {
        isExpired(at: Date())
    }

    public var remainingMinutes: Int {
        remainingMinutes(at: Date())
    }

    public func isExpired(at date: Date) -> Bool {
        date.timeIntervalSince(timestamp) > Double(windowMinutes * 60)
    }

    public func remainingMinutes(at date: Date) -> Int {
        let elapsed = Int(date.timeIntervalSince(timestamp) / 60)
        return max(0, windowMinutes - elapsed)
    }
}

public enum RunRecoveryRules {
    /// Calculates optimal post-run nutritional recovery target based on run intensity and duration.
    /// Standard sports nutrition guidelines:
    /// - Carbs: ~1.0g to 1.2g per kg of body weight for moderate-to-long runs (>30 mins or >400 kcal), scaled by energy expenditure.
    /// - Protein: ~0.3g per kg (~25g-35g standard dose) to stimulate muscle protein synthesis.
    /// - Hydration: ~1.3 mL to 1.5 mL per kcal burned or estimated fluid loss.
    public static func calculateTarget(
        for run: Run,
        weightLbs: Double = 165.0
    ) -> RunRecoveryTarget? {
        let kcal = run.activeCalories ?? RunEnergy.estimateKcal(distanceMeters: run.distanceMeters, weightLbs: weightLbs)
        // Require at least 2 km or 15 minutes of running or 150 kcal to trigger a formal glycogen refuel alert
        guard run.distanceMeters >= 2000 || kcal >= 150 || run.movingSeconds >= 900 else {
            return nil
        }
        let kg = weightLbs * 0.45359237

        // Scale carbs by distance / kcal: roughly 0.5g/kg for shorter runs up to 1.2g/kg for long runs (>15 km)
        let carbRatio = min(1.2, max(0.5, (run.distanceMeters / 1000) * 0.08))
        let carbs = Int((kg * carbRatio).rounded())

        // Protein dose: standard 25-35g range, scaling up to 0.6g/kg (max ~45g) for long strenuous efforts (>1500 kcal)
        let proteinRatio = min(0.6, max(0.25, kcal / 1500.0 + 0.25))
        let protein = min(45, max(20, Int((kg * proteinRatio).rounded())))

        // Hydration: roughly 1.3 mL per kcal burned
        let rehydrateML = Int((kcal * 1.3).rounded())

        return RunRecoveryTarget(
            targetCarbGrams: carbs,
            targetProteinGrams: protein,
            rehydrateMilliLiters: rehydrateML,
            windowMinutes: 45,
            runDistanceMeters: run.distanceMeters,
            activeCalories: kcal,
            runID: run.id,
            timestamp: run.endDate
        )
    }
}
