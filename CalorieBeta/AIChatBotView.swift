import SwiftUI
import FirebaseFirestore
import FirebaseAuth

func capitalizedFirstLetter(of string: String) -> String {
    guard let first = string.first else { return "" }
    return first.uppercased() + string.dropFirst()
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let isUser: Bool
}

struct MaiaActionPayload: Codable, Identifiable {
    var id: UUID { UUID() }
    let type: String?
    let mealName: String?
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fats: Double?
    
    let exerciseName: String?
    let durationMinutes: Int?
    let caloriesBurned: Double?
    
    let amountOunces: Double?
    let fastHours: Int?
    let weightPounds: Double?
}

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

enum MaiaAction {
    case generateMealPlan
    case logWorkout(exerciseName: String, durationMinutes: Int, caloriesBurned: Double)
    case logWater(amountOunces: Double)
    case startFast(hours: Int)
    case stopFast
    case logWeight(weightPounds: Double)
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

private struct AIChatActionCard: View {
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

private struct AIChatMealPlanActionCard: View {
    let onConfirm: () -> Void
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("7-Day Meal Plan")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                    Text("Includes grocery list generation")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(.white.opacity(0.8))
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

private struct AIChatWorkoutActionCard: View {
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

private struct AIChatWaterActionCard: View {
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

private struct AIChatFastActionCard: View {
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

private struct AIChatWeightActionCard: View {
    let weightPounds: Double
    let onConfirm: () -> Void
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
                MacroLabel(title: "Weight", value: String(format: "%.1f lbs", weightPounds), color: .white, bgColor: .white.opacity(0.2))
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

private struct MacroLabel: View {
    let title: String
    let value: String
    var color: Color = .textPrimary
    var bgColor: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color == .white ? .white.opacity(0.8) : Color(UIColor.secondaryLabel))
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(bgColor ?? color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ChatHistoryListView: View {
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

private struct MaiaBriefingCard: View {
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

private struct MaiaDailyContextRow: View {
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

private struct MaiaContextChip: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
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

private struct MaiaBriefingMetric: View {
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

private struct MaiaHealthKitContextIndicator: View {
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

struct AIChatbotView: View {
    @State private var userMessage = ""
    @State private var chatMessages: [ChatMessage] = []
    @State private var isLoading = false
    @Binding var selectedTab: Int
    var chatContext: String?

    var bgGreen = Color(red: 16/255, green: 20/255, blue: 21/255)

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel

    @Environment(\.colorScheme) var colorScheme
    @StateObject private var ttsManager = TTSManager.shared

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showingClearChatConfirmation = false

    private var bottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    private var starterSuggestions: [String] {
        var suggestions: [String] = []

        if relevantDailyLog?.calorieConsistencyStatus().hasMeaningfulMismatch == true {
            suggestions.append("Audit today's calorie and macro mismatch.")
        }

        if remainingProtein >= 15 {
            suggestions.append("Help me hit \(Int(remainingProtein.rounded()))g more protein.")
        }

        if workoutCount > 0 {
            suggestions.append("What should I eat after today's workout?")
        }

        if mealCount == 0 {
            suggestions.append("Build my first meal for today.")
        } else {
            suggestions.append("What should I eat with \(Int(remainingCalories.rounded())) calories left?")
        }

        suggestions.append("Give me a simple dinner idea.")
        suggestions.append("Log 1 apple and a handful of almonds.")

        return Array(suggestions.prefix(4))
    }

    var body: some View {
        VStack(spacing: 0) {
            if chatMessages.count <= 1 {
                MaiaBriefingCard(
	                    calories: remainingCalories,
	                    protein: remainingProtein,
	                    carbs: remainingCarbs,
	                    fats: remainingFats,
	                    water: waterOunces,
	                    waterGoal: waterGoal,
	                    mealCount: mealCount,
	                    workoutCount: workoutCount
	                )
                .padding(.horizontal)
                .padding(.top, 10)

                if healthKitViewModel.isAuthorized {
                    MaiaHealthKitContextIndicator(
                        steps: healthKitViewModel.todaySteps,
                        activeEnergy: healthKitViewModel.todayActiveEnergy,
                        sleepSummary: healthKitViewModel.sleepSummary
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            ChatHistoryListView(
                chatMessages: $chatMessages,
                onLogRecipe: logRecipe,
                onSpeak: ttsManager.speak,
                onAction: handleMaiaAction,
                showAlert: $showAlert,
                alertMessage: $alertMessage
            )
            .onTapGesture { hideKeyboard() }

            VStack(spacing: 0) {
                if chatMessages.count <= 1 && !isLoading {
                    SuggestionButtonsView(suggestions: starterSuggestions) { prompt in
                        userMessage = prompt
                        sendMessage()
                    }
                    .padding(.vertical, 10)
                }

                if isLoading {
                    HStack(alignment: .bottom, spacing: 10) {
                        Image("maia_avatar")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .background(Color.backgroundSecondary, in: Circle())
                        
                        MaiaTypingIndicator()
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                HStack(spacing: 10) {
                    TextField("Ask Maia anything...", text: $userMessage, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.backgroundPrimary.opacity(colorScheme == .dark ? 0.62 : 0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .lineLimit(1...4)
                        .onSubmit(sendMessage)

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(
                                userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                                ? Color(UIColor.tertiaryLabel)
                                : Color.brandPrimary,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, bottomSafeAreaInset)
            }
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(
                        Rectangle().frame(height: 1).foregroundColor(Color.primary.opacity(0.05)),
                        alignment: .top
                    )
            )
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Maia")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingClearChatConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(chatMessages.count <= 1)
            }
        }
        .onAppear(perform: setupView)
        .onDisappear(perform: saveMessages)
        .onReceive(appState.$pendingChatPrompt) { prompt in
            if let prompt = prompt {
                userMessage = prompt
                sendMessage()
                appState.pendingChatPrompt = nil
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Notification"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog("Clear Maia chat?", isPresented: $showingClearChatConfirmation, titleVisibility: .visible) {
            Button("Clear Chat", role: .destructive, action: clearChat)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the saved conversation history on this device.")
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func setupView() {
        loadMessages()
        if let userID = Auth.auth().currentUser?.uid {
            dailyLogService.fetchLog(for: userID, date: dailyLogService.activelyViewedDate) { _ in }
        }
        if chatMessages.isEmpty {
            let welcomeMessage = "Hello! I’m Maia, your personal nutrition assistant. How can I assist you right now?"
            let initialMessage = ChatMessage(id: UUID(), text: welcomeMessage, isUser: false)
            chatMessages.append(initialMessage)
        }
    }

    private func clearChat() {
        chatMessages.removeAll()
        let welcomeMessage = "Fresh chat ready. What would you like help with?"
        chatMessages.append(ChatMessage(id: UUID(), text: welcomeMessage, isUser: false))
        saveMessages()
    }

    private var remainingCalories: Double {
        let total = relevantDailyLog?.totalCalories() ?? 0
        let goal = goalSettings.calories ?? 2000
        return max(0, goal - total)
    }

    private var remainingProtein: Double {
        let total = relevantDailyLog?.totalMacros().protein ?? 0
        return max(0, goalSettings.protein - total)
    }

    private var remainingFats: Double {
        let total = relevantDailyLog?.totalMacros().fats ?? 0
        return max(0, goalSettings.fats - total)
    }

    private var remainingCarbs: Double {
        let total = relevantDailyLog?.totalMacros().carbs ?? 0
        return max(0, goalSettings.carbs - total)
    }

    private var mealCount: Int {
        relevantDailyLog?.meals.filter { !$0.foodItems.isEmpty }.count ?? 0
    }

    private var workoutCount: Int {
        relevantDailyLog?.exercises?.count ?? 0
    }

    private var waterOunces: Double {
        relevantDailyLog?.waterTracker?.totalOunces ?? 0
    }

    private var waterGoal: Double {
        relevantDailyLog?.waterTracker?.goalOunces ?? goalSettings.waterGoal
    }

    private var dailyContextSummary: String {
        let log = relevantDailyLog
        let macros = log?.totalMacros() ?? (protein: 0, fats: 0, carbs: 0)
        let caloriesLogged = log?.totalCalories() ?? 0
        let consistencyStatus = log?.calorieConsistencyStatus()
        let flaggedFoods = log?.foodsWithMeaningfulCalorieMacroMismatch().map(\.name).prefix(4).joined(separator: ", ") ?? "None"
        let exerciseNames = log?.exercises?.map(\.name).joined(separator: ", ") ?? "None"

        let hkSteps = healthKitViewModel.todaySteps
        let hkActiveEnergy = healthKitViewModel.todayActiveEnergy
        let sleepHours = healthKitViewModel.sleepSummary.lastNightHours
        let sleepScore = healthKitViewModel.sleepSummary.lastNightScore ?? healthKitViewModel.sleepSummary.averageScore
        let macroCalories = consistencyStatus?.macroDerivedCalories ?? 0
        let calorieDelta = consistencyStatus?.delta ?? 0
        let auditStatus = consistencyStatus?.hasMeaningfulMismatch == true
            ? "Needs review: macros imply \(Int(abs(calorieDelta).rounded())) calories \(calorieDelta > 0 ? "more" : "less") than logged."
            : "No meaningful mismatch."

        return """
        Today's logged context:
        - Calories logged: \(Int(caloriesLogged.rounded())) of \(Int((goalSettings.calories ?? 0).rounded())) target
        - Macro-derived calories: \(Int(macroCalories.rounded()))
        - Nutrition audit: \(auditStatus)
        - Flagged foods: \(flaggedFoods)
        - Protein logged: \(Int(macros.protein.rounded()))g of \(Int(goalSettings.protein.rounded()))g target
        - Carbs logged: \(Int(macros.carbs.rounded()))g of \(Int(goalSettings.carbs.rounded()))g target
        - Fats logged: \(Int(macros.fats.rounded()))g of \(Int(goalSettings.fats.rounded()))g target
        - Meals logged: \(mealCount)
        - Water logged: \(Int(waterOunces.rounded())) oz of \(Int(waterGoal.rounded())) oz target
        - Workouts logged: \(workoutCount) (\(exerciseNames))

        User coaching preferences:
        - Training intent: \(goalSettings.trainingIntent)
        - Reminder style: \(goalSettings.reminderStyle)
        - Maia style: \(goalSettings.maiaTone)

        Passive Health Data (For Coaching Context Only):
        - Steps Today: \(Int(hkSteps))
        - Passive Active Energy Burned: \(Int(hkActiveEnergy)) kcal
        - Sleep Last Night: \(String(format: "%.1f", sleepHours)) hours
        - Sleep Score: \(sleepScore.map { "\($0)" } ?? "Unavailable")
        """
    }

    private var relevantDailyLog: DailyLog? {
        let logDate = dailyLogService.activelyViewedDate
        return dailyLogService.currentDailyLog.flatMap { log in
            Calendar.current.isDate(log.date, inSameDayAs: logDate) ? log : nil
        }
    }

    func sendMessage() {
        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        let userMsg = ChatMessage(id: UUID(), text: trimmedMessage, isUser: true)
        chatMessages.append(userMsg)
        AnalyticsManager.aiFeatureUsed(.maiaChat)
        HapticManager.instance.feedback(.light)

        let msgToSend = userMessage
        userMessage = ""
        isLoading = true
        hideKeyboard()

        fetchGPT3Response(for: msgToSend) { aiResponse in
            let aiMsg = ChatMessage(id: UUID(), text: aiResponse, isUser: false)
            chatMessages.append(aiMsg)
            isLoading = false
            HapticManager.instance.feedback(.light)
        }
    }

    func fetchGPT3Response(for message: String, completion: @escaping (String) -> Void) {
        let systemPrompt = """
        You are Maia, the personal nutrition and training coach inside MyFitPlate.
        Your style is warm, concise, practical, and specific to the user's logged day. Avoid generic wellness filler.
        Do not diagnose medical conditions or present estimates as clinical truth.
        Respect the user's coaching preferences in the context. If reminder style is Minimal, be brief. If Direct, be crisp and action-oriented. If Gentle, be encouraging without being vague.
        If the nutrition audit says calories and macros meaningfully disagree, mention that logged calories remain official but the item should be reviewed before making precise calorie-budget claims.

        You have the ability to automatically perform actions for the user! When the user asks you to log a workout, generate a meal plan, log a meal, log water, start/stop a fast, or log their weight, you MUST provide a structured JSON block AT THE END of your message.
        
        Action: Generate Meal Plan (and Grocery List)
        (Note: this action ALWAYS generates a full 7-day meal plan overwriting their current week. If the user asks for a shorter plan, tell them this tool generates a full week but you can suggest single meals instead. Do not output text for the meal plan yourself if you are using this action, just say "I've prepared a 7-day meal plan for you. Tap the button below to generate it!" and then use the json block.)
        ```json
        {
          "type": "generate_meal_plan"
        }
        ```
        
        Action: Log Workout
        ```json
        {
          "type": "log_workout",
          "exerciseName": "Running",
          "durationMinutes": 30,
          "caloriesBurned": 300
        }
        ```
        
        Action: Log Meal (or suggest a meal)
        ```json
        {
          "type": "meal_suggestion",
          "mealName": "Chicken & Rice",
          "calories": 400,
          "protein": 30,
          "carbs": 40,
          "fats": 10
        }
        ```
        
        Action: Log Water
        ```json
        {
          "type": "log_water",
          "amountOunces": 16
        }
        ```
        
        Action: Start Fast
        ```json
        {
          "type": "start_fast",
          "fastHours": 16
        }
        ```
        
        Action: Stop Fast
        ```json
        {
          "type": "stop_fast"
        }
        ```
        
        Action: Log Weight
        ```json
        {
          "type": "log_weight",
          "weightPounds": 150.5
        }
        ```

        You may include conversational text BEFORE the JSON block. Do not include any text after the JSON block.
        If data is missing, say what assumption you are making.
        For your own AI estimates, keep calories reasonably consistent with protein*4 + carbs*4 + fats*9. Do not invent exact precision for restaurant or packaged foods.

        **User's Remaining Goals for Today:**
        - Calories: \(String(format: "%.0f", self.remainingCalories)) cal
        - Protein: \(String(format: "%.0f", self.remainingProtein)) g
        - Fats: \(String(format: "%.0f", self.remainingFats)) g
        - Carbs: \(String(format: "%.0f", self.remainingCarbs)) g

        \(dailyContextSummary)
        \(chatContext.map { "Additional context: \($0)" } ?? "")
        """

        var messagesForAPI: [[String: Any]] = [["role": "system", "content": systemPrompt]]

        let history = chatMessages.dropLast().suffix(6)
        for chatMessage in history {
            if !chatMessage.text.isEmpty {
                messagesForAPI.append(["role": chatMessage.isUser ? "user" : "assistant", "content": chatMessage.text])
            }
        }

        messagesForAPI.append(["role": "user", "content": message])

        Task { @MainActor in
            let result = await AIService.shared.performRequest(
                messages: messagesForAPI,
                model: "gpt-4o-mini",
                maxTokens: 1000,
                temperature: 0.5
            )

            switch result {
            case .success(let content):
                completion(content)
            case .failure(let error):
                AppLog.ai.error("Maia chat request failed: \(error.localizedDescription, privacy: .public)")
                completion("I couldn't reach Maia's deeper model right now. Based on your logged day, focus first on protein, hydration, and a simple meal that fits your remaining calories.")
            }
        }
    }

    private func extractFoodName(from aiResponse: String) -> String {
        let lines = aiResponse.split(separator: "\n", maxSplits: 5, omittingEmptySubsequences: true).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let patterns = ["recipe for\\s+(.*?)(?:\\s*\\(.*?\\))?[:\n]", "estimate for\\s+(.*?)(?:\\s*\\(.*?\\))?[:\n]", "details for\\s+(.*?)(?:\\s*\\(.*?\\))?[:\n]", "for\\s+(.*?)(?:\\s*\\(.*?\\))?[:\n]"]
        for line in lines.prefix(3) {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                    if let match = regex.firstMatch(in: line, options: [], range: nsRange) {
                        if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: line) {
                            var foodNameCandidate = String(line[range])
                            foodNameCandidate = foodNameCandidate.replacingOccurrences(of: "\\s+recipe$", with: "", options: .regularExpression, range: nil)
                            foodNameCandidate = foodNameCandidate.replacingOccurrences(of: "\\s+estimate$", with: "", options: .regularExpression, range: nil)
                            foodNameCandidate = foodNameCandidate.replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
                            foodNameCandidate = foodNameCandidate.replacingOccurrences(of: "_", with: " ")
                            foodNameCandidate = foodNameCandidate.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–")))
                            if !foodNameCandidate.isEmpty && foodNameCandidate.count < 70 && foodNameCandidate.lowercased() != "this" {
                                return capitalizedFirstLetter(of: foodNameCandidate)
                            }
                        }
                    }
                }
            }
        }
        if let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let commonGreetings = ["sure!", "okay,", "alright,", "certainly,", "great!", "got it,", "no problem,", "here's a", "here is a"]
            let lowerFirstLine = firstLine.lowercased()
            var potentialTitle = firstLine
            if commonGreetings.contains(where: { lowerFirstLine.starts(with: $0) }) {
                for greeting in commonGreetings {
                    if lowerFirstLine.starts(with: greeting) {
                        potentialTitle = String(potentialTitle.dropFirst(greeting.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
            if let colonIndex = potentialTitle.firstIndex(of: ":") { potentialTitle = String(potentialTitle[..<colonIndex]) }
            potentialTitle = potentialTitle.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–")))
            potentialTitle = potentialTitle.replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
            potentialTitle = potentialTitle.replacingOccurrences(of: "_", with: " ")
            if !potentialTitle.isEmpty && potentialTitle.count < 70 && !potentialTitle.lowercased().contains("nutritional breakdown") {
                return capitalizedFirstLetter(of: potentialTitle)
            }
        }
        return "AI Logged Food"
    }

    func logRecipe(recipeText: String) {
        guard let userID = Auth.auth().currentUser?.uid else { alertMessage = "Not logged in."; showAlert = true; return }
        let nutritionalBreakdown = parseNutritionalBreakdown(from: recipeText)
        guard let calories = nutritionalBreakdown["calories"], let protein = nutritionalBreakdown["protein"], let fats = nutritionalBreakdown["fats"], let carbs = nutritionalBreakdown["carbs"] else {
            alertMessage = "Missing macro info in AI response. Please try asking in a different way."; showAlert = true; return
        }
        let calcium = nutritionalBreakdown["calcium"]; let iron = nutritionalBreakdown["iron"]
        let potassium = nutritionalBreakdown["potassium"]; let sodium = nutritionalBreakdown["sodium"]
        let vitaminA = nutritionalBreakdown["vitaminA"]; let vitaminC = nutritionalBreakdown["vitaminC"]
        let vitaminD = nutritionalBreakdown["vitaminD"]
        let foodName = extractFoodName(from: recipeText)
        let loggedFoodItem = FoodItem(id: UUID().uuidString, name: foodName, calories: calories, protein: protein, carbs: carbs, fats: fats, servingSize: "1 serving (AI Est.)", servingWeight: 0, timestamp: Date(), calcium: calcium, iron: iron, potassium: potassium, sodium: sodium, vitaminA: vitaminA, vitaminC: vitaminC, vitaminD: vitaminD)
        let mealType = determineMealType()
        dailyLogService.addMealToLog(for: userID, date: dailyLogService.activelyViewedDate, mealName: mealType, foodItems: [loggedFoodItem], source: "ai_chat")
        let haptic = UINotificationFeedbackGenerator(); haptic.notificationOccurred(.success); alertMessage = "\(foodName) logged!"; showAlert = true
        Task { @MainActor in self.achievementService.checkFeatureUsedAchievement(userID: userID, featureType: .aiRecipeLogged) }
    }

    private func handleMaiaAction(_ action: MaiaAction) {
        guard let userID = Auth.auth().currentUser?.uid else {
            alertMessage = "Not logged in."
            showAlert = true
            return
        }

        switch action {
        case .generateMealPlan:
            // Route to Meal Planner
            Task {
                let success = await mealPlannerService.generateAndSaveFullWeekPlan(
                    goals: goalSettings,
                    preferredFoods: [],
                    preferredCuisines: [],
                    preferredSnacks: [],
                    userID: userID
                )
                
                await MainActor.run {
                    if success {
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                        alertMessage = "Meal Plan generated! Check the Meal Plan tab."
                    } else {
                        alertMessage = "Failed to generate meal plan. Please try again."
                    }
                    showAlert = true
                }
            }
        case .logWorkout(let exerciseName, let durationMinutes, let caloriesBurned):
            dailyLogService.addWorkoutToCurrentLog(
                for: userID,
                exerciseName: exerciseName,
                durationMinutes: durationMinutes,
                caloriesBurned: caloriesBurned
            )
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            alertMessage = "\(exerciseName) logged!"
            showAlert = true
            
        case .logWater(let amountOunces):
            dailyLogService.addWaterToCurrentLog(for: userID, amount: amountOunces, goalOunces: goalSettings.waterGoal)
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            alertMessage = "\(Int(amountOunces.rounded())) oz of water logged!"
            showAlert = true
            
        case .startFast(let hours):
            FastingManager.shared.startFast(hours: hours)
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            alertMessage = "Started a \(hours)-hour fast!"
            showAlert = true
            
        case .stopFast:
            FastingManager.shared.endFast()
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            alertMessage = "Fast ended!"
            showAlert = true
            
        case .logWeight(let weightPounds):
            HealthKitManager.shared.saveWeightSample(weightLbs: weightPounds, date: Date())
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            alertMessage = "Weight updated to \(String(format: "%.1f", weightPounds)) lbs!"
            showAlert = true
        }
    }

    private func parseNutrient(from text: String, for nutrient: String) -> Double? {
        do {
            let regex = try NSRegularExpression(pattern: "\(nutrient):\\s*([\\d.]+)", options: .caseInsensitive)
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: nsRange),
               let range = Range(match.range(at: 1), in: text) {
                return Double(text[range])
            }
        } catch {
            AppLog.ai.error("Failed to parse nutrient \(nutrient, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private func parseNutritionalBreakdown(from recipeText: String) -> [String: Double] {
        var breakdown: [String: Double] = [:]
        breakdown["calories"] = parseNutrient(from: recipeText, for: "Calories")
        breakdown["protein"] = parseNutrient(from: recipeText, for: "Protein")
        breakdown["carbs"] = parseNutrient(from: recipeText, for: "Carbs")
        breakdown["fats"] = parseNutrient(from: recipeText, for: "Fats")
        breakdown["calcium"] = parseNutrient(from: recipeText, for: "Calcium")
        breakdown["iron"] = parseNutrient(from: recipeText, for: "Iron")
        breakdown["potassium"] = parseNutrient(from: recipeText, for: "Potassium")
        breakdown["sodium"] = parseNutrient(from: recipeText, for: "Sodium")
        breakdown["vitaminA"] = parseNutrient(from: recipeText, for: "Vitamin A")
        breakdown["vitaminC"] = parseNutrient(from: recipeText, for: "Vitamin C")
        breakdown["vitaminD"] = parseNutrient(from: recipeText, for: "Vitamin D")
        return breakdown
    }

    private func determineMealType() -> String { let h = Calendar.current.component(.hour, from: Date()); switch h { case 0..<4: return "Snack"; case 4..<11: return "Breakfast"; case 11..<16: return "Lunch"; case 16..<21: return "Dinner"; default: return "Snack" } }

    private func loadMessages() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let key = "chatHistory_\(userID)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decodedMessages = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            self.chatMessages = decodedMessages
        }
    }

    private func saveMessages() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let key = "chatHistory_\(userID)"
        let max = 12
        let messagesToSave = Array(chatMessages.suffix(max))

        if let encoded = try? JSONEncoder().encode(messagesToSave) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
import SwiftUI

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

private struct DotView: View {
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
