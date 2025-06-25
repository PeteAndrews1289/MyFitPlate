import Foundation
import HealthKit
import Combine
import FirebaseAuth

@MainActor
class HealthKitViewModel: ObservableObject {

    @Published var isAuthorized = false
    @Published var workouts: [LoggedExercise] = []
    @Published var sleepSamples: [HKCategorySample] = []
    @Published var authError: String? = nil
    @Published var isSyncing = false

    private let manager = HealthKitManager.shared
    private weak var dailyLogService: DailyLogService?

    func setup(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
        checkAuthorizationStatus()
    }

    func requestAuthorization() {
        manager.requestAuthorization { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    self?.fetchTodayWorkouts()
                    self?.fetchLastSevenDaysSleep()
                } else {
                    let errorMessage = error?.localizedDescription ?? "An unknown error occurred."
                    self?.authError = errorMessage
                }
            }
        }
    }

    func checkAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { self.isAuthorized = false }
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        manager.healthStore.getRequestStatusForAuthorization(toShare: [], read: typesToRead) { [weak self] (status, error) in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    self.isAuthorized = false
                    return
                }
                
                switch status {
                case .unnecessary:
                    self.isAuthorized = true
                    self.fetchTodayWorkouts()
                    self.fetchLastSevenDaysSleep()
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

    func fetchTodayWorkouts() {
        guard isAuthorized, !isSyncing else { return }
        isSyncing = true
        manager.fetchWorkouts(for: Date()) { [weak self] (hkWorkouts, error) in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { self.isSyncing = false }
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
    
    func fetchLastSevenDaysSleep() {
        guard isAuthorized else { return }
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) else { return }
        
        manager.fetchSleepAnalysis(startDate: startDate, endDate: endDate) { [weak self] (samples, error) in
            guard let self = self, let samples = samples, error == nil else { return }
            self.sleepSamples = samples
        }
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
        guard let userID = Auth.auth().currentUser?.uid, let dailyLogService = self.dailyLogService else {
            DispatchQueue.main.async { self.isSyncing = false }
            return
        }
        
        dailyLogService.addOrUpdateHealthKitWorkouts(for: userID, exercises: workouts, date: Date()) {
            DispatchQueue.main.async {
                self.isSyncing = false
            }
        }
    }
}

extension HKWorkoutActivityType {
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
