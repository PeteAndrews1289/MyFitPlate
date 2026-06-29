import Foundation
import HealthKit
import Combine
public struct SleepHealthSummary: Equatable {
    public var lastNightScore: Int?
    public var averageScore: Int?
    public var lastNightHours: Double
    public var averageHours: Double
    public var sampleCount: Int
    public var nightCount: Int
    public var lastSleepDate: Date?

    static let empty = SleepHealthSummary(
        lastNightScore: nil,
        averageScore: nil,
        lastNightHours: 0,
        averageHours: 0,
        sampleCount: 0,
        nightCount: 0,
        lastSleepDate: nil
    )
}

@MainActor
public class HealthKitViewModel: ObservableObject {
    public init() {}

    @Published public var isAuthorized = false
    @Published public var workouts: [LoggedExercise] = []
    @Published public var sleepSamples: [HKCategorySample] = []
    @Published public var sleepSummary: SleepHealthSummary = .empty
    @Published public var todaySteps: Double = 0
    @Published public var todayActiveEnergy: Double = 0
    
    // Comprehensive Weekly Trends
    @Published public var weeklySteps: [Double] = Array(repeating: 0, count: 7)
    @Published public var weeklyActiveEnergy: [Double] = Array(repeating: 0, count: 7)
    @Published public var weeklyRestingHeartRate: [Double] = Array(repeating: 0, count: 7)
    @Published public var weeklyHRV: [Double] = Array(repeating: 0, count: 7)
    
    @Published public var authError: String? = nil
    @Published public var isSyncing = false

    /// The moment we last successfully READ non-empty data from HealthKit — the only honest proof
    /// that read access actually works. `getRequestStatusForAuthorization` returns `.unnecessary`
    /// whether the user granted OR denied reads (iOS deliberately hides read denials), so it can
    /// never be trusted on its own to mean "connected."
    @Published public var lastSyncedAt: Date?

    private let manager = HealthKitManager.shared
    private weak var dailyLogService: DailyLogService?

    public func setup(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
        checkAuthorizationStatus()
    }

    public func requestAuthorization() {
        manager.requestAuthorization { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    self?.syncAllHealthData()
                } else {
                    let errorMessage = error?.localizedDescription ?? "An unknown error occurred."
                    self?.authError = errorMessage
                }
            }
        }
    }

    public func checkAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { self.isAuthorized = false }
            return
        }

        guard let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let sleepAnalysisType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            DispatchQueue.main.async { self.isAuthorized = false }
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            activeEnergyType,
            sleepAnalysisType,
            stepCountType
        ]

        manager.healthStore.getRequestStatusForAuthorization(toShare: [], read: typesToRead) { [weak self] (status, error) in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    AppLog.app.error("Failed to check HealthKit authorization status: \(error.localizedDescription, privacy: .public)")
                    self.isAuthorized = false
                    return
                }

                switch status {
                case .unnecessary:
                    // ".unnecessary" only means iOS won't show a prompt — it does NOT prove the
                    // user granted read access (a denied read looks identical). We optimistically
                    // attempt a sync; `lastSyncedAt` is the honest signal of whether data actually flows.
                    self.isAuthorized = true
                    self.syncAllHealthData()
                case .shouldRequest:
                    self.isAuthorized = false
                case .unknown:
                    self.isAuthorized = false
                @unknown default:
                    self.isAuthorized = false
                }
            }
        }
    }

    public func syncAllHealthData() {
        guard isAuthorized else { return }
        fetchTodayWorkouts()
        fetchLastSevenDaysSleep()
        fetchTodayPassiveData()
        fetchComprehensiveWeeklyData()
    }

    public func fetchComprehensiveWeeklyData() {
        guard isAuthorized else { return }
        
        manager.fetch7DayTrend(for: .stepCount, options: .cumulativeSum, unit: .count()) { [weak self] data in
            DispatchQueue.main.async { self?.weeklySteps = data }
        }
        
        manager.fetch7DayTrend(for: .activeEnergyBurned, options: .cumulativeSum, unit: .kilocalorie()) { [weak self] data in
            DispatchQueue.main.async { self?.weeklyActiveEnergy = data }
        }
        
        manager.fetch7DayTrend(for: .restingHeartRate, options: .discreteAverage, unit: HKUnit.count().unitDivided(by: .minute())) { [weak self] data in
            DispatchQueue.main.async { self?.weeklyRestingHeartRate = data }
        }
        
        manager.fetch7DayTrend(for: .heartRateVariabilitySDNN, options: .discreteAverage, unit: .secondUnit(with: .milli)) { [weak self] data in
            DispatchQueue.main.async { self?.weeklyHRV = data }
        }
    }

    public func fetchTodayPassiveData() {
        guard isAuthorized else { return }

        manager.fetchTodaySteps { [weak self] steps in
            DispatchQueue.main.async {
                self?.todaySteps = steps
                // A non-zero read is concrete proof read access is working.
                if steps > 0 { self?.lastSyncedAt = Date() }
            }
        }

        manager.fetchTodayActiveEnergy { [weak self] activeEnergy in
            DispatchQueue.main.async {
                self?.todayActiveEnergy = activeEnergy
            }
        }
    }

    public func fetchTodayWorkouts() {
        guard isAuthorized, !isSyncing else { return }
        isSyncing = true
        manager.fetchWorkouts(for: Date()) { [weak self] (hkWorkouts, error) in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    AppLog.app.error("Failed to fetch HealthKit workouts: \(error.localizedDescription, privacy: .public)")
                    self.isSyncing = false
                }
                return
            }
            guard let workouts = hkWorkouts else {
                DispatchQueue.main.async { self.isSyncing = false }
                return
            }
            let loggedExercises = workouts.map { self.mapHKWorkoutToLoggedExercise($0) }
            self.workouts = loggedExercises
            self.syncWorkoutsWithFirestore(loggedExercises)
        }
    }

    public func fetchLastSevenDaysSleep() {
        guard isAuthorized else { return }
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) else { return }

        manager.fetchSleepAnalysis(startDate: startDate, endDate: endDate) { [weak self] (samples, error) in
            guard let self = self else { return }
            if let error {
                AppLog.health.error("Failed to fetch seven-day sleep samples: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let samples = samples else {
                self.sleepSamples = []
                self.sleepSummary = .empty
                return
            }
            self.sleepSamples = samples
            self.sleepSummary = self.makeSleepSummary(from: samples)
            AppLog.health.info("Fetched \(samples.count, privacy: .public) HealthKit sleep samples across \(self.sleepSummary.nightCount, privacy: .public) nights.")
        }
    }

    private struct SleepNight {
        var date: Date
        var asleep: TimeInterval = 0
        var awake: TimeInterval = 0
        var bedtime: Date?
    }

    private func makeSleepSummary(from samples: [HKCategorySample]) -> SleepHealthSummary {
        let calendar = Calendar.current
        let sleepByNight = Dictionary(grouping: samples) { sleepNightKey(for: $0, calendar: calendar) }
        var validNights: [SleepNight] = []

        for (nightKey, relevantSamples) in sleepByNight {
            let asleepSamples = relevantSamples.filter {
                guard let value = HKCategoryValueSleepAnalysis(rawValue: $0.value) else { return false }
                return value == .asleepCore || value == .asleepDeep || value == .asleepREM || value == .asleepUnspecified
            }
            let awakeSamples = relevantSamples.filter { HKCategoryValueSleepAnalysis(rawValue: $0.value) == .awake }

            let timeAsleep = calculateTotalDuration(from: asleepSamples)
            let timeAwake = calculateTotalDuration(from: awakeSamples)
            
            if timeAsleep > 0 {
                let bedtime = asleepSamples.map { $0.startDate }.min()
                validNights.append(SleepNight(date: nightKey, asleep: timeAsleep, awake: timeAwake, bedtime: bedtime))
            }
        }

        validNights.sort { $0.date < $1.date }

        guard !validNights.isEmpty else {
            return .empty
        }

        let bedtimes = validNights.compactMap(\.bedtime)
        let usualBedtimeMinutes = averageBedtimeMinutes(from: bedtimes)
        let scoredNights = validNights.map { night in
            calculateSleepScore(
                asleep: night.asleep,
                awake: night.awake,
                bedtimeComponent: bedtimeScore(for: night.bedtime, usualBedtimeMinutes: usualBedtimeMinutes)
            )
        }

        let averageScore = scoredNights.reduce(0, +) / max(scoredNights.count, 1)
        let averageHours = validNights.reduce(0) { $0 + $1.asleep / 3600.0 } / Double(validNights.count)
        let lastNight = validNights.last
        let lastScore = scoredNights.last

        return SleepHealthSummary(
            lastNightScore: lastScore,
            averageScore: averageScore,
            lastNightHours: (lastNight?.asleep ?? 0) / 3600.0,
            averageHours: averageHours,
            sampleCount: samples.count,
            nightCount: validNights.count,
            lastSleepDate: lastNight?.date
        )
    }

    private func sleepNightKey(for sample: HKCategorySample, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: sample.startDate)
        let normalizedDate = hour < 18 ? calendar.date(byAdding: .day, value: -1, to: sample.startDate) ?? sample.startDate : sample.startDate
        return calendar.startOfDay(for: normalizedDate)
    }

    private func calculateTotalDuration(from samples: [HKCategorySample]) -> TimeInterval {
        let intervals = samples.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = [sorted[0]]
        for interval in sorted.dropFirst() {
            let lastIndex = merged.count - 1
            let last = merged[lastIndex]
            if interval.start <= last.end {
                if interval.end > last.end {
                    merged[lastIndex] = DateInterval(start: last.start, end: interval.end)
                }
            } else {
                merged.append(interval)
            }
        }
        return merged.reduce(0) { $0 + $1.duration }
    }

    private func averageBedtimeMinutes(from bedtimes: [Date]) -> Double? {
        guard bedtimes.count > 1 else { return nil }
        let minutes = bedtimes.map { bedtimeMinutes(from: $0) }
        return minutes.reduce(0, +) / Double(minutes.count)
    }

    private func bedtimeMinutes(from date: Date) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0)
        let minute = Double(components.minute ?? 0)
        return hour < 12 ? (hour + 24) * 60 + minute : hour * 60 + minute
    }

    private func bedtimeScore(for bedtime: Date?, usualBedtimeMinutes: Double?) -> Double {
        guard let bedtime, let usualBedtimeMinutes else { return 22.5 }

        let deviation = abs(bedtimeMinutes(from: bedtime) - usualBedtimeMinutes)
        if deviation <= 15 { return 30 }
        if deviation <= 30 { return 26 }
        if deviation <= 60 { return 21 }
        if deviation <= 90 { return 16 }
        if deviation <= 120 { return 11 }
        return 6
    }

    private func calculateSleepScore(asleep: TimeInterval, awake: TimeInterval, bedtimeComponent: Double) -> Int {
        let totalHoursAsleep = asleep / 3600.0
        guard totalHoursAsleep > 0 else { return 0 }

        let score = durationScore(hours: totalHoursAsleep)
            + bedtimeComponent
            + interruptionScore(asleep: asleep, awake: awake)

        return Int(max(0, min(100, round(score))))
    }

    private func durationScore(hours: Double) -> Double {
        if hours >= 7 && hours <= 9 { return 50 }
        if hours > 9 { return max(30, 50 - ((hours - 9) * 5)) }
        if hours >= 6 { return min(50, 30 + ((hours - 6) * 25)) }
        return max(0, (hours / 6) * 30)
    }

    private func interruptionScore(asleep: TimeInterval, awake: TimeInterval) -> Double {
        let totalTime = max(asleep, asleep + awake)
        guard totalTime > 0 else { return 0 }

        let awakePercentage = (awake / totalTime) * 100
        if awakePercentage <= 8 { return 20 }
        if awakePercentage <= 20 { return max(10, 20 - ((awakePercentage - 8) * 0.8)) }
        return max(0, 10 - ((awakePercentage - 20) * 0.6))
    }

    private func mapHKWorkoutToLoggedExercise(_ workout: HKWorkout) -> LoggedExercise {
        return LoggedExercise(
            id: workout.uuid.uuidString,
            name: workout.workoutActivityType.name,
            durationMinutes: Int(workout.duration / 60),
            caloriesBurned: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
            date: workout.startDate,
            source: "HealthKit"
        )
    }

    private func syncWorkoutsWithFirestore(_ workouts: [LoggedExercise]) {
        guard let userID = DIContainer.shared.authService.currentUserID, let dailyLogService = self.dailyLogService else {
            DispatchQueue.main.async { self.isSyncing = false }
            return
        }

        dailyLogService.exerciseLogStore.addOrUpdateHealthKitWorkouts(for: userID, exercises: workouts, date: Date()) {
            DispatchQueue.main.async {
                self.isSyncing = false
            }
        }
    }
}

public extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .americanFootball: return "American Football"
        case .archery: return "Archery"
        case .australianFootball: return "Australian Football"
        case .badminton: return "Badminton"
        case .baseball: return "Baseball"
        case .basketball: return "Basketball"
        case .bowling: return "Bowling"
        case .boxing: return "Boxing"
        case .climbing: return "Climbing"
        case .cricket: return "Cricket"
        case .crossTraining: return "Cross Training"
        case .curling: return "Curling"
        case .cycling: return "Cycling"
        case .dance: return "Dance"
        case .danceInspiredTraining: return "Dance Training"
        case .elliptical: return "Elliptical"
        case .equestrianSports: return "Equestrian Sports"
        case .fencing: return "Fencing"
        case .fishing: return "Fishing"
        case .functionalStrengthTraining: return "Functional Strength Training"
        case .golf: return "Golf"
        case .gymnastics: return "Gymnastics"
        case .handball: return "Handball"
        case .hiking: return "Hiking"
        case .hockey: return "Hockey"
        case .hunting: return "Hunting"
        case .lacrosse: return "Lacrosse"
        case .martialArts: return "Martial Arts"
        case .mindAndBody: return "Mind and Body"
        case .mixedMetabolicCardioTraining: return "Cardio Training"
        case .paddleSports: return "Paddle Sports"
        case .play: return "Play"
        case .preparationAndRecovery: return "Preparation and Recovery"
        case .racquetball: return "Racquetball"
        case .rowing: return "Rowing"
        case .rugby: return "Rugby"
        case .running: return "Running"
        case .sailing: return "Sailing"
        case .skatingSports: return "Skating"
        case .snowSports: return "Snow Sports"
        case .soccer: return "Soccer"
        case .softball: return "Softball"
        case .squash: return "Squash"
        case .stairClimbing: return "Stair Climbing"
        case .surfingSports: return "Surfing"
        case .swimming: return "Swimming"
        case .tableTennis: return "Table Tennis"
        case .tennis: return "Tennis"
        case .trackAndField: return "Track and Field"
        case .traditionalStrengthTraining: return "Strength Training"
        case .volleyball: return "Volleyball"
        case .walking: return "Walking"
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .waterSports: return "Water Sports"
        case .wrestling: return "Wrestling"
        case .yoga: return "Yoga"
        case .barre: return "Barre"
        case .coreTraining: return "Core Training"
        case .crossCountrySkiing: return "Cross Country Skiing"
        case .downhillSkiing: return "Downhill Skiing"
        case .flexibility: return "Flexibility"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope: return "Jump Rope"
        case .kickboxing: return "Kickboxing"
        case .pilates: return "Pilates"
        case .snowboarding: return "Snowboarding"
        case .stairs: return "Stairs"
        case .stepTraining: return "Step Training"
        case .wheelchairWalkPace: return "Wheelchair Walk Pace"
        case .wheelchairRunPace: return "Wheelchair Run Pace"
        case .taiChi: return "Tai Chi"
        case .mixedCardio: return "Mixed Cardio"
        case .handCycling: return "Hand Cycling"
        default: return "Workout"
        }
    }
}
