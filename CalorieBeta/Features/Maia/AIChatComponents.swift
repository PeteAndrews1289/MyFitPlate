import SwiftUI

struct SuggestionButtonsView: View {
    let suggestions: [String]
    var onSelect: (String) -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try asking...")
                .appFont(size: 16, weight: .semibold)
                .foregroundColor(.textPrimary)
                .padding(.horizontal)
                .padding(.bottom, 5)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: { onSelect(suggestion) }) {
                        Text(suggestion)
                            .appFont(size: 14, weight: .medium)
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .padding(10)
                            .background(Color.backgroundSecondary.opacity(0.74), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct ChatBubble: View {
    @Environment(\.colorScheme) var colorScheme

    let message: ChatMessage
    let onLogRecipe: (String) -> Void
    let onSpeak: (String) -> Void
    let onAction: (MaiaAction) -> Void
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    private let canBeLogged: Bool

    init(message: ChatMessage, onLogRecipe: @escaping (String) -> Void, onSpeak: @escaping (String) -> Void, onAction: @escaping (MaiaAction) -> Void, showAlert: Binding<Bool>, alertMessage: Binding<String>) {
        self.message = message
        self.onLogRecipe = onLogRecipe
        self.onSpeak = onSpeak
        self.onAction = onAction
        self._showAlert = showAlert
        self._alertMessage = alertMessage
        self.canBeLogged = !message.isUser && message.text.contains("---Nutritional Breakdown---") && message.text.contains("Calories:")
    }

    private func parseStructuredPayloads(from text: String) -> (String, [MaiaActionPayload]) {
        var cleanText = text
        var payloads: [MaiaActionPayload] = []

        let pattern = "```json\\s*(\\{.*?\\})\\s*```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches.reversed() {
                let jsonString = nsString.substring(with: match.range(at: 1))
                if let data = jsonString.data(using: .utf8),
                   let payload = try? JSONDecoder().decode(MaiaActionPayload.self, from: data) {
                    payloads.append(payload)
                }
                cleanText = (cleanText as NSString).replacingCharacters(in: match.range, with: "")
            }
        }

        return (cleanText.trimmingCharacters(in: .whitespacesAndNewlines), payloads.reversed())
    }

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                if message.isUser {
                    Spacer(minLength: 42)
                } else {
                    Image("maia_avatar")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                        .background(Color.backgroundSecondary, in: Circle())
                }

                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                    Text(message.isUser ? "You" : "Maia")
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    let parsed = parseStructuredPayloads(from: message.text)
                    let displayText = parsed.0
                    let payloads = parsed.1

                    if !displayText.isEmpty {
                        Text(.init(displayText))
                            .appFont(size: 15)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(
                                Group {
                                    if message.isUser {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(LinearGradient.brandGradient)
                                    } else {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(message.isUser ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: message.isUser ? Color.brandPrimary.opacity(0.3) : Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                            .foregroundColor(message.isUser ? .white : .textPrimary)
                            .frame(maxWidth: 310, alignment: message.isUser ? .trailing : .leading)
                    }

                    if !payloads.isEmpty && !message.isUser {
                        ForEach(payloads) { payload in
                            if payload.type == "meal_suggestion" || payload.type == nil {
                                if let name = payload.mealName, let c = payload.calories, let p = payload.protein, let cb = payload.carbs, let f = payload.fats {
                                    AIChatActionCard(mealName: name, calories: c, protein: p, carbs: cb, fats: f, onLog: {
                                        let legacyFormat = """
                                        \(name)
                                        ---Nutritional Breakdown---
                                        Calories: \(c)
                                        Protein: \(p)g
                                        Carbs: \(cb)g
                                        Fats: \(f)g
                                        """
                                        onLogRecipe(legacyFormat)
                                    })
                                    .frame(maxWidth: 310, alignment: .leading)
                                }
                            } else if payload.type == "generate_meal_plan" {
                                AIChatMealPlanActionCard(onConfirm: {
                                    onAction(.generateMealPlan)
                                })
                                .frame(maxWidth: 310, alignment: .leading)
                            } else if payload.type == "log_workout" {
                                if let ex = payload.exerciseName, let d = payload.durationMinutes, let c = payload.caloriesBurned {
                                    AIChatWorkoutActionCard(exerciseName: ex, durationMinutes: d, caloriesBurned: c, onConfirm: {
                                        onAction(.logWorkout(exerciseName: ex, durationMinutes: d, caloriesBurned: c))
                                    })
                                    .frame(maxWidth: 310, alignment: .leading)
                                }
                            } else if payload.type == "log_water" {
                                if let oz = payload.amountOunces {
                                    AIChatWaterActionCard(amountOunces: oz, onConfirm: {
                                        onAction(.logWater(amountOunces: oz))
                                    })
                                    .frame(maxWidth: 310, alignment: .leading)
                                }
                            } else if payload.type == "start_fast" {
                                AIChatFastActionCard(fastHours: payload.fastHours, isStop: false, onConfirm: {
                                    onAction(.startFast(hours: payload.fastHours ?? 16))
                                })
                                .frame(maxWidth: 310, alignment: .leading)
                            } else if payload.type == "stop_fast" {
                                AIChatFastActionCard(fastHours: nil, isStop: true, onConfirm: {
                                    onAction(.stopFast)
                                })
                                .frame(maxWidth: 310, alignment: .leading)
                            } else if payload.type == "log_weight" {
                                if let w = payload.weightPounds {
                                    AIChatWeightActionCard(weightPounds: w, onConfirm: {
                                        onAction(.logWeight(weightPounds: w))
                                    })
                                    .frame(maxWidth: 310, alignment: .leading)
                                }
                            }
                        }
                    }
                }

                if !message.isUser {
                    Spacer(minLength: 42)
                }
            }

            HStack(spacing: 12) {
                if message.isUser { Spacer() }
                if !message.isUser {
                    Button(action: { onSpeak(message.text) }) {
                        Label("Speak", systemImage: "speaker.wave.2.fill")
                            .appFont(size: 12, weight: .semibold)
                    }
                    .foregroundColor(.brandPrimary)
                    .buttonStyle(.plain)
                }
                if canBeLogged {
                    Button(action: { onLogRecipe(message.text) }) {
                        Label("Log Food", systemImage: "plus.circle.fill")
                            .appFont(size: 12, weight: .semibold)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(LinearGradient.brandGradient, in: Capsule())
                            .foregroundColor(.white)
                            .shadow(color: Color.brandPrimary.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                if !message.isUser { Spacer() }
            }
            .padding(.leading, message.isUser ? 0 : 44)
            .padding(.trailing, message.isUser ? 44 : 0)
        }
    }
}

struct AIChatActionCard: View {
    let mealName: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    let onLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(mealName)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                Spacer()
                Button(action: onLog) {
                    Text("Log Food")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                        .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 3)
                }
                .buttonStyle(AnimatedCardButtonStyle())
            }

            HStack(spacing: 12) {
                MacroLabel(title: "Cal", value: "\(Int(calories.rounded()))", color: .white, bgColor: .white.opacity(0.2))
                MacroLabel(title: "Pro", value: "\(Int(protein.rounded()))g", color: .white, bgColor: .white.opacity(0.2))
                MacroLabel(title: "Carb", value: "\(Int(carbs.rounded()))g", color: .white, bgColor: .white.opacity(0.2))
                MacroLabel(title: "Fat", value: "\(Int(fats.rounded()))g", color: .white, bgColor: .white.opacity(0.2))
            }
        }
        .padding(16)
        .background(
            LinearGradient.brandGradient,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: Color.brandPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct AIChatMealPlanActionCard: View {
    let onConfirm: () -> Void
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("7-Day Meal Plan")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("Includes grocery list generation")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer()
                Button(action: {
                    didConfirm = true
                    onConfirm()
                }) {
                    Text(didConfirm ? "Generated" : "Generate")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didConfirm ? .white : .brandPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(didConfirm ? Color.white.opacity(0.2) : Color.white, in: Capsule())
                }
                .disabled(didConfirm)
                .buttonStyle(AnimatedCardButtonStyle())
            }
        }
        .padding(16)
        .background(
            LinearGradient.brandGradient,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: Color.brandPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct AIChatWorkoutActionCard: View {
    let exerciseName: String
    let durationMinutes: Int
    let caloriesBurned: Double
    let onConfirm: () -> Void
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(exerciseName)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                Spacer()
                Button(action: {
                    didConfirm = true
                    onConfirm()
                }) {
                    Text(didConfirm ? "Logged" : "Log Workout")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didConfirm ? .white : .brandPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(didConfirm ? Color.white.opacity(0.2) : Color.white, in: Capsule())
                }
                .disabled(didConfirm)
                .buttonStyle(AnimatedCardButtonStyle())
            }

            HStack(spacing: 12) {
                MacroLabel(title: "Time", value: "\(durationMinutes)m", color: .white, bgColor: .white.opacity(0.2))
                MacroLabel(title: "Burn", value: "\(Int(caloriesBurned.rounded())) kcal", color: .white, bgColor: .white.opacity(0.2))
            }
        }
        .padding(16)
        .background(
            LinearGradient.brandGradient,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: Color.brandPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct AIChatWaterActionCard: View {
    let amountOunces: Double
    let onConfirm: () -> Void
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Log Water")
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    didConfirm = true
                    onConfirm()
                }) {
                    Text(didConfirm ? "Logged" : "Confirm")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didConfirm ? .white : .brandPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(didConfirm ? Color.white.opacity(0.2) : Color.white, in: Capsule())
                }
                .disabled(didConfirm)
                .buttonStyle(AnimatedCardButtonStyle())
            }

            HStack(spacing: 12) {
                MacroLabel(title: "Amount", value: "\(Int(amountOunces.rounded())) oz", color: .white, bgColor: .white.opacity(0.2))
            }
        }
        .padding(16)
        .background(
            LinearGradient.brandGradient,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: Color.brandPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct AIChatFastActionCard: View {
    let fastHours: Int?
    let isStop: Bool
    let onConfirm: () -> Void
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isStop ? "End Fast" : "Start Fast")
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    didConfirm = true
                    onConfirm()
                }) {
                    Text(didConfirm ? "Confirmed" : "Confirm")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didConfirm ? .white : .brandPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(didConfirm ? Color.white.opacity(0.2) : Color.white, in: Capsule())
                }
                .disabled(didConfirm)
                .buttonStyle(AnimatedCardButtonStyle())
            }

            if let hours = fastHours, !isStop {
                HStack(spacing: 12) {
                    MacroLabel(title: "Duration", value: "\(hours) hrs", color: .white, bgColor: .white.opacity(0.2))
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient.brandGradient,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: Color.brandPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct AIChatWeightActionCard: View {
    let weightPounds: Double
    let onConfirm: () -> Void
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Log Weight")
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    didConfirm = true
                    onConfirm()
                }) {
                    Text(didConfirm ? "Logged" : "Confirm")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didConfirm ? .white : .brandPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(didConfirm ? Color.white.opacity(0.2) : Color.white, in: Capsule())
                }
                .disabled(didConfirm)
                .buttonStyle(AnimatedCardButtonStyle())
            }

            HStack(spacing: 12) {
                MacroLabel(title: "Weight", value: String(format: "%.1f %@", BodyUnits.weightDisplayValue(lbs: weightPounds, metric: useMetric), BodyUnits.weightUnit(metric: useMetric)), color: .white, bgColor: .white.opacity(0.2))
            }
        }
        .padding(16)
        .background(
            LinearGradient.brandGradient,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: Color.brandPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct MacroLabel: View {
    let title: String
    let value: String
    var color: Color = .textPrimary
    var bgColor: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(color == .white ? .white.opacity(0.8) : Color(UIColor.secondaryLabel))
            Text(value)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(bgColor ?? color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ChatHistoryListView: View {
    @Binding var chatMessages: [ChatMessage]
    var onLogRecipe: (String) -> Void
    var onSpeak: (String) -> Void
    var onAction: (MaiaAction) -> Void
    @Binding var showAlert: Bool
    @Binding var alertMessage: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(chatMessages) { message in
                        ChatBubble(
                            message: message,
                            onLogRecipe: onLogRecipe,
                            onSpeak: onSpeak,
                            onAction: onAction,
                            showAlert: $showAlert,
                            alertMessage: $alertMessage
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onChange(of: chatMessages) {
                if let lastId = chatMessages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let lastId = chatMessages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }
}

struct MaiaBriefingCard: View {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    let water: Double
    let waterGoal: Double
    let mealCount: Int
    let workoutCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image("maia_avatar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                    .background(Color.backgroundSecondary, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Maia is ready")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Ask for food ideas, meal logging, recipe help, or a quick read on today.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            MaiaDailyContextRow(
                mealCount: mealCount,
                workoutCount: workoutCount,
                water: water,
                waterGoal: waterGoal
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                MaiaBriefingMetric(title: "Calories left", value: "\(Int(calories.rounded()))", color: .orange)
                MaiaBriefingMetric(title: "Protein left", value: "\(Int(protein.rounded()))g", color: .accentProtein)
                MaiaBriefingMetric(title: "Carbs left", value: "\(Int(carbs.rounded()))g", color: .accentCarbs)
                MaiaBriefingMetric(title: "Fats left", value: "\(Int(fats.rounded()))g", color: .accentFats)
            }
        }
        .asCard()
    }
}

struct MaiaDailyContextRow: View {
    let mealCount: Int
    let workoutCount: Int
    let water: Double
    let waterGoal: Double

    var body: some View {
        HStack(spacing: 8) {
            MaiaContextChip(icon: "fork.knife", title: "\(mealCount)", subtitle: mealCount == 1 ? "meal" : "meals", color: .orange)
            MaiaContextChip(icon: "figure.strengthtraining.traditional", title: "\(workoutCount)", subtitle: workoutCount == 1 ? "workout" : "workouts", color: .brandPrimary)
            MaiaContextChip(icon: "drop.fill", title: "\(Int(water.rounded()))", subtitle: "/ \(Int(waterGoal.rounded())) oz", color: .blue)
        }
    }
}

struct MaiaContextChip: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .appFont(size: 11, weight: .bold)
                .foregroundColor(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 10, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct MaiaBriefingMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .appFont(size: 16, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct MaiaHealthKitContextIndicator: View {
    let steps: Double
    let activeEnergy: Double
    let sleepSummary: SleepHealthSummary

    var body: some View {
        let sleepHours = sleepSummary.lastNightHours
        let sleepScore = sleepSummary.lastNightScore ?? sleepSummary.averageScore

        HStack(spacing: 8) {
            Image(systemName: "applewatch")
                .foregroundColor(.brandPrimary)
            Text("Maia is analyzing your HealthKit data")
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(.secondary)
            Spacer()

            HStack(spacing: 12) {
                if steps > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                        Text("\(Int(steps))")
                    }
                }
                if activeEnergy > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text("\(Int(activeEnergy))")
                    }
                }
                if sleepHours > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.zzz.fill")
                        Text(String(format: "%.1fh", sleepHours))
                    }
                }
                if let sleepScore {
                    HStack(spacing: 4) {
                        Image(systemName: "bed.double.fill")
                        Text("\(sleepScore)")
                    }
                }
            }
            .appFont(size: 11, weight: .bold)
            .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct MaiaTypingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 5) {
            DotView(isAnimating: $isAnimating, delay: 0.0)
            DotView(isAnimating: $isAnimating, delay: 0.2)
            DotView(isAnimating: $isAnimating, delay: 0.4)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .onAppear {
            isAnimating = true
        }
    }
}

struct DotView: View {
    @Binding var isAnimating: Bool
    let delay: Double
    
    var body: some View {
        Circle()
            .fill(Color.brandPrimary)
            .frame(width: 7, height: 7)
            .offset(y: isAnimating ? -4 : 4)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: isAnimating
            )
    }
}
