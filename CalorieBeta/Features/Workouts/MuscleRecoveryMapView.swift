import SwiftUI
import FirebaseAuth

struct MuscleRecovery: Identifiable {
    var id: String { group.rawValue }
    let group: MuscleGroup
    let lastTrained: Date?
    let lastSessionSets: Int
    let recoveryHours: Double

    private var hoursSince: Double? {
        guard let lastTrained else { return nil }
        return max(0, Date().timeIntervalSince(lastTrained) / 3600)
    }

    var isUntrained: Bool { lastTrained == nil }

    var isReady: Bool {
        guard let hoursSince else { return false }
        return hoursSince >= recoveryHours
    }

    /// Fully recovered AND not trained in over a week — a "you should hit this" nudge.
    var isOverdue: Bool {
        guard let hoursSince else { return false }
        return hoursSince >= recoveryHours && hoursSince >= 8 * 24
    }

    var hoursUntilReady: Double {
        guard let hoursSince else { return 0 }
        return max(0, recoveryHours - hoursSince)
    }

    /// 0…1 ring fill, eased so it climbs a bit faster toward "ready". Untrained shows empty.
    var recoveryPercentage: Double {
        guard let hoursSince else { return 0 }
        let t = min(1.0, hoursSince / max(recoveryHours, 1))
        return 1 - (1 - t) * (1 - t)
    }

    var etaText: String? {
        if isUntrained || isReady { return nil }
        let h = hoursUntilReady
        if h < 1 { return "Ready soon" }
        if h < 20 { return "Ready in ~\(Int(h.rounded()))h" }
        let days = Int((h / 24).rounded(.up))
        return days <= 1 ? "Ready tomorrow" : "Ready in ~\(days) days"
    }
    
    var statusColor: Color {
        if isUntrained { return .secondary }
        let percent = recoveryPercentage
        if percent < 0.34 {
            return .red
        } else if percent < 0.67 {
            return .orange
        } else if percent < 1.0 {
            return .yellow
        } else {
            return .accentPositive
        }
    }
    
    var statusText: String {
        if isUntrained { return "Untrained" }
        if isReady { return isOverdue ? "Ready · Overdue" : "Fresh & Ready" }
        let percent = recoveryPercentage
        if percent < 0.34 {
            return "Fatigued"
        } else if percent < 0.67 {
            return "Recovering"
        } else {
            return "Almost Ready"
        }
    }
}

struct MuscleRecoveryMapView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @StateObject private var workoutService = WorkoutService()
    @State private var recoveries: [MuscleRecovery] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "figure.mind.and.body")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Muscle Recovery Map")
                        .appFont(size: 19, weight: .bold)
                        .foregroundColor(.textPrimary)
                    
                    Text("Adjusted for how hard you trained each muscle and your recent sleep.")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            recommendationBanner

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(recoveries) { recovery in
                    muscleCard(for: recovery)
                }
            }
            .padding(.top, 4)
        }
        .asCard()
        .onAppear(perform: calculateRecovery)
        .onChange(of: dailyLogService.currentDailyLog) { _, _ in
            calculateRecovery()
        }
    }
    
    @ViewBuilder
    private func muscleCard(for recovery: MuscleRecovery) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.backgroundSecondary, lineWidth: 4)
                
                Circle()
                    .trim(from: 0, to: recovery.recoveryPercentage)
                    .stroke(recovery.statusColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: recovery.recoveryPercentage)
                
                Image(systemName: recovery.group.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(recovery.statusColor)
            }
            .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(recovery.group.rawValue)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)
                
                Text(recovery.statusText)
                    .appFont(size: 10, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)

                if let eta = recovery.etaText {
                    Text(eta)
                        .appFont(size: 9, weight: .semibold)
                        .foregroundColor(.brandPrimary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func calculateRecovery() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        let lookbackDays = 14
        let startDate = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now)!
        let sleepScore = healthKitViewModel.sleepSummary.lastNightScore ?? healthKitViewModel.sleepSummary.averageScore

        Task {
            var lastTrained: [MuscleGroup: Date] = [:]
            var lastSessionSets: [MuscleGroup: Int] = [:]

            func record(_ muscleSets: [MuscleGroup: Int], at date: Date) {
                for (group, sets) in muscleSets where date > (lastTrained[group] ?? .distantPast) {
                    lastTrained[group] = date
                    lastSessionSets[group] = sets
                }
            }

            // Primary source: completed routine sessions carry the real exercise names.
            // (The daily log only stores one summary entry named after the routine, so matching
            // muscle keywords against it misses almost everything — that was the stale-map bug.)
            let sessions = await workoutService.fetchRecentSessionLogs(sinceDays: lookbackDays)
            for session in sessions {
                var muscleSets: [MuscleGroup: Int] = [:]
                for completed in session.completedExercises {
                    for g in extractMuscleGroups(from: completed.exerciseName.lowercased()) {
                        muscleSets[g, default: 0] += completed.sets.count
                    }
                }
                record(muscleSets, at: session.date.dateValue())
            }

            // Secondary source: manually-logged exercises in the daily log.
            let result = await dailyLogService.fetchDailyHistory(for: userID, startDate: startDate, endDate: now)
            if case .success(let logs) = result {
                for log in logs {
                    guard let exercises = log.exercises else { continue }
                    var muscleSets: [MuscleGroup: Int] = [:]
                    for exercise in exercises {
                        for g in extractMuscleGroups(from: exercise.name.lowercased()) {
                            muscleSets[g, default: 0] += 6
                        }
                    }
                    if !muscleSets.isEmpty { record(muscleSets, at: log.date) }
                }
            }

            let wellnessMult = Self.wellnessMultiplier(sleepScore)
            await MainActor.run {
                self.recoveries = MuscleGroup.allCases.map { group in
                    let sets = lastSessionSets[group]
                    let hours = Self.recoveryWindowHours(group: group, sets: sets, wellnessMultiplier: wellnessMult)
                    return MuscleRecovery(group: group, lastTrained: lastTrained[group], lastSessionSets: sets ?? 0, recoveryHours: hours)
                }
            }
        }
    }
    
    static func wellnessMultiplier(_ sleepScore: Int?) -> Double {
        guard let s = sleepScore, s > 0 else { return 1.0 }
        if s >= 80 { return 0.9 }   // great sleep → recover faster
        if s >= 60 { return 1.0 }
        if s >= 40 { return 1.1 }
        return 1.2                  // poor sleep → recover slower
    }

    static func recoveryWindowHours(group: MuscleGroup, sets: Int?, wellnessMultiplier: Double) -> Double {
        let base: Double
        switch group {
        case .legs, .back: base = 64       // large, eccentric-heavy movers recover slowest
        case .chest: base = 56
        case .shoulders, .core: base = 44
        case .arms: base = 40              // small muscles bounce back fastest
        }
        let intensity = sets.map { min(1.5, max(0.8, 0.6 + Double($0) * 0.06)) } ?? 1.0
        return base * intensity * wellnessMultiplier
    }

    private var recommendationBanner: some View {
        let ready = recoveries.filter { $0.isReady && !$0.isUntrained && !$0.isOverdue }.map { $0.group.rawValue }
        let overdue = recoveries.filter { $0.isOverdue }.map { $0.group.rawValue }
        return Group {
            if !ready.isEmpty || !overdue.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !ready.isEmpty {
                        Label {
                            Text("Ready to train: \(ready.joined(separator: ", "))")
                                .appFont(size: 13, weight: .semibold)
                                .foregroundColor(.textPrimary)
                        } icon: {
                            Image(systemName: "bolt.fill").foregroundColor(.accentPositive)
                        }
                    }
                    if !overdue.isEmpty {
                        Label {
                            Text("Overdue: \(overdue.joined(separator: ", ")) — give these a session soon.")
                                .appFont(size: 13, weight: .semibold)
                                .foregroundColor(.textPrimary)
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.brandPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func extractMuscleGroups(from name: String) -> [MuscleGroup] {
        var groups = [MuscleGroup]()
        
        if name.contains("bench") || name.contains("chest") || name.contains("pushup") || name.contains("fly") {
            groups.append(.chest)
        }
        if name.contains("row") || name.contains("pullup") || name.contains("lat") || name.contains("back") || name.contains("deadlift") {
            groups.append(.back)
        }
        if name.contains("squat") || name.contains("leg") || name.contains("lunge") || name.contains("calf") || name.contains("glute") || name.contains("deadlift") {
            groups.append(.legs)
        }
        if name.contains("curl") || name.contains("tricep") || name.contains("arm") || name.contains("pushdown") || name.contains("extension") {
            groups.append(.arms)
        }
        if name.contains("crunch") || name.contains("plank") || name.contains("ab") || name.contains("situp") || name.contains("core") {
            groups.append(.core)
        }
        if name.contains("shoulder") || name.contains("lateral") || name.contains("overhead") || name.contains("raise") || name.contains("press") {
            // Wait, "bench press" could trigger shoulders too if "press" is in it, which is somewhat accurate.
            groups.append(.shoulders)
        }
        
        return groups
    }
}
