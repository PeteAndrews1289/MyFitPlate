import Foundation

public struct PlateLoad: Equatable, Identifiable, Sendable {
    public let weight: Double
    public let countPerSide: Int

    public var id: Double { weight }

    public init(weight: Double, countPerSide: Int) {
        self.weight = weight
        self.countPerSide = countPerSide
    }
}

public struct PlateLoadout: Equatable, Sendable {
    public let targetWeight: Double
    public let barWeight: Double
    public let loadedWeight: Double
    public let difference: Double
    public let platesPerSide: [PlateLoad]

    public var isExact: Bool { difference < 0.001 }
    public var totalPlateCount: Int {
        platesPerSide.reduce(0) { $0 + ($1.countPerSide * 2) }
    }

    public init(
        targetWeight: Double,
        barWeight: Double,
        loadedWeight: Double,
        difference: Double,
        platesPerSide: [PlateLoad]
    ) {
        self.targetWeight = targetWeight
        self.barWeight = barWeight
        self.loadedWeight = loadedWeight
        self.difference = difference
        self.platesPerSide = platesPerSide
    }
}

public enum PlateLoadingRules {
    public static let standardBarWeight = 45.0
    public static let standardPlateWeights = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5]
    public static let maximumSupportedWeight = 10_000.0

    public static func loadout(
        targetWeight: Double,
        barWeight: Double = standardBarWeight,
        availablePlates: [Double] = standardPlateWeights
    ) -> PlateLoadout? {
        guard targetWeight.isFinite,
              barWeight.isFinite,
              targetWeight >= barWeight,
              barWeight > 0,
              targetWeight <= maximumSupportedWeight else {
            return nil
        }

        let plates = Array(Set(availablePlates.filter {
            $0.isFinite && $0 > 0 && $0 <= maximumSupportedWeight
        })).sorted(by: >)

        var remainingPerSide = (targetWeight - barWeight) / 2
        var plateLoads: [PlateLoad] = []

        for plate in plates where remainingPerSide >= plate - 0.000_1 {
            let count = Int(floor((remainingPerSide + 0.000_1) / plate))
            guard count > 0 else { continue }
            plateLoads.append(PlateLoad(weight: plate, countPerSide: count))
            remainingPerSide = max(0, remainingPerSide - (Double(count) * plate))
        }

        let loadedPlateWeight = plateLoads.reduce(0.0) {
            $0 + ($1.weight * Double($1.countPerSide) * 2)
        }
        let loadedWeight = barWeight + loadedPlateWeight
        let difference = max(0, targetWeight - loadedWeight)

        return PlateLoadout(
            targetWeight: targetWeight,
            barWeight: barWeight,
            loadedWeight: loadedWeight,
            difference: difference,
            platesPerSide: plateLoads
        )
    }
}

public struct NutritionTrendSummary: Equatable, Sendable {
    public let observedDays: Int
    public let averageCalories: Double?
    public let averageProtein: Double?
    public let averageCarbs: Double?
    public let averageFat: Double?

    public init(
        observedDays: Int,
        averageCalories: Double?,
        averageProtein: Double?,
        averageCarbs: Double?,
        averageFat: Double?
    ) {
        self.observedDays = observedDays
        self.averageCalories = averageCalories
        self.averageProtein = averageProtein
        self.averageCarbs = averageCarbs
        self.averageFat = averageFat
    }
}

public enum NutritionTrendRules {
    public static func validPoints(_ points: [DateValuePoint]) -> [DateValuePoint] {
        points
            .filter { $0.value.isFinite && $0.value >= 0 }
            .sorted { $0.date < $1.date }
    }

    public static func validGoal(_ goal: Double?) -> Double? {
        guard let goal, goal.isFinite, goal > 0 else { return nil }
        return goal
    }

    public static func finiteNonnegative(_ value: Double) -> Double? {
        guard value.isFinite, value >= 0 else { return nil }
        return value
    }

    public static func summary(
        calories: [DateValuePoint],
        protein: [DateValuePoint],
        carbs: [DateValuePoint],
        fat: [DateValuePoint],
        calendar: Calendar = .current
    ) -> NutritionTrendSummary {
        let validSeries = [calories, protein, carbs, fat].map(validPoints)
        let observedDates = Set(validSeries.flatMap { series in
            series.map { calendar.startOfDay(for: $0.date) }
        })

        return NutritionTrendSummary(
            observedDays: observedDates.count,
            averageCalories: average(validSeries[0]),
            averageProtein: average(validSeries[1]),
            averageCarbs: average(validSeries[2]),
            averageFat: average(validSeries[3])
        )
    }

    private static func average(_ points: [DateValuePoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.reduce(0) { $0 + $1.value } / Double(points.count)
    }
}
