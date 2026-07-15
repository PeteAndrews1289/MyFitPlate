import MyFitPlateCore

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

struct MaiaActionBoardView: View {
    let remainingCalories: Double
    let remainingProtein: Double
    let waterRemaining: Double
    let hasWorkoutToday: Bool
    let hasNutritionMismatch: Bool
    let healthKitEnabled: Bool
    let pantryCount: Int
    let isGeneratingMeal: Bool
    var onFillMacros: () -> Void
    var onProteinOrRecovery: () -> Void
    var onTrustOrToday: () -> Void
    var onHydrate: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum ActionKind: String, CaseIterable, Identifiable {
        case fillMacros
        case proteinOrRecovery
        case trustOrToday
        case hydrate

        var id: String { rawValue }
    }

    private var proteinCardTitle: String {
        hasWorkoutToday ? "Recovery meal" : "Protein anchor"
    }

    private var proteinCardSubtitle: String? {
        if hasWorkoutToday {
            return "\(Int(remainingProtein.rounded()))g left"
        }
        return remainingProtein >= 15 ? "\(Int(remainingProtein.rounded()))g left" : nil
    }

    private var trustCardTitle: String {
        hasNutritionMismatch ? "Review trust" : "Read today"
    }

    private var recommendedAction: ActionKind {
        if hasNutritionMismatch { return .trustOrToday }
        if hasWorkoutToday && remainingProtein >= 10 { return .proteinOrRecovery }
        if remainingCalories >= 150 { return .fillMacros }
        if waterRemaining > 0 { return .hydrate }
        return .trustOrToday
    }

    private var secondaryActions: [ActionKind] {
        ActionKind.allCases.filter { $0 != recommendedAction }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            Button(action: { perform(recommendedAction) }) {
                HStack(alignment: .top, spacing: AppSpacing.row) {
                    Group {
                        if recommendedAction == .fillMacros && isGeneratingMeal {
                            ProgressView()
                        } else {
                            Image(systemName: icon(for: recommendedAction))
                                .appFont(size: 18, weight: .bold)
                                .foregroundStyle(tint(for: recommendedAction))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(
                        tint(for: recommendedAction).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Best next step")
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(title(for: recommendedAction))
                            .appTextRole(.sectionTitle)
                            .foregroundStyle(AppPalette.text)

                        Text(recommendationSummary(for: recommendedAction))
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: AppSpacing.compact)

                    Image(systemName: "arrow.right")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.brandText)
                        .accessibilityHidden(true)
                }
                .appSurface(.emphasized, radius: AppRadius.hero)
            }
            .buttonStyle(.plain)
            .disabled(recommendedAction == .fillMacros && isGeneratingMeal)
            .accessibilityIdentifier("maia_recommended_action")

            MaiaDataBoundaryStrip(
                healthKitEnabled: healthKitEnabled,
                pantryCount: pantryCount
            )

            Text("More options")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    ForEach(secondaryActions) { action in
                        secondaryActionChip(action, showsSubtitle: true)
                    }
                }
            } else {
                HStack(spacing: AppSpacing.compact) {
                    ForEach(secondaryActions) { action in
                        secondaryActionChip(action, showsSubtitle: false)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func title(for action: ActionKind) -> String {
        switch action {
        case .fillMacros: "Fill macros"
        case .proteinOrRecovery: proteinCardTitle
        case .trustOrToday: trustCardTitle
        case .hydrate: "Hydrate"
        }
    }

    private func subtitle(for action: ActionKind) -> String? {
        switch action {
        case .fillMacros: "\(Int(remainingCalories.rounded())) cal"
        case .proteinOrRecovery: proteinCardSubtitle
        case .trustOrToday: nil
        case .hydrate: waterRemaining > 0 ? "+16 oz" : "Covered"
        }
    }

    private func icon(for action: ActionKind) -> String {
        switch action {
        case .fillMacros: "fork.knife.circle.fill"
        case .proteinOrRecovery:
            hasWorkoutToday ? "bolt.heart.fill" : "figure.strengthtraining.traditional"
        case .trustOrToday:
            hasNutritionMismatch ? "exclamationmark.shield.fill" : "checkmark.shield.fill"
        case .hydrate: "drop.fill"
        }
    }

    private func tint(for action: ActionKind) -> Color {
        switch action {
        case .fillMacros: AppPalette.energy
        case .proteinOrRecovery: hasWorkoutToday ? .accentSignal : .accentProtein
        case .trustOrToday: hasNutritionMismatch ? AppPalette.caution : .accentPositive
        case .hydrate: .accentWater
        }
    }

    private func recommendationSummary(for action: ActionKind) -> String {
        switch action {
        case .fillMacros:
            "\(Int(remainingCalories.rounded()).formatted()) calories remain in today's target."
        case .proteinOrRecovery:
            hasWorkoutToday
                ? "You trained today and have \(Int(remainingProtein.rounded()).formatted())g protein left."
                : "You have \(Int(remainingProtein.rounded()).formatted())g protein left today."
        case .trustOrToday:
            hasNutritionMismatch
                ? "A nutrition mismatch is worth reviewing before you use today's totals."
                : "See what today's food, water, and training point to."
        case .hydrate:
            "\(Int(waterRemaining.rounded()).formatted()) oz remains toward today's water target."
        }
    }

    private func perform(_ action: ActionKind) {
        switch action {
        case .fillMacros: onFillMacros()
        case .proteinOrRecovery: onProteinOrRecovery()
        case .trustOrToday: onTrustOrToday()
        case .hydrate: onHydrate()
        }
    }

    private func isDisabled(_ action: ActionKind) -> Bool {
        switch action {
        case .fillMacros: isGeneratingMeal
        case .hydrate: waterRemaining <= 0
        case .proteinOrRecovery, .trustOrToday: false
        }
    }

    private func secondaryActionChip(_ action: ActionKind, showsSubtitle: Bool) -> some View {
        MaiaActionChip(
            title: title(for: action),
            subtitle: showsSubtitle ? subtitle(for: action) : nil,
            icon: icon(for: action),
            tint: tint(for: action),
            isLoading: action == .fillMacros && isGeneratingMeal,
            isDisabled: isDisabled(action),
            fillsWidth: true,
            action: { perform(action) }
        )
    }
}

private struct MaiaActionChip: View {
    let title: String
    let subtitle: String?
    let icon: String
    let tint: Color
    var isLoading = false
    var isDisabled = false
    var fillsWidth = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: icon)
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(tint)
                }

                Text(title)
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text("· \(subtitle)")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                if fillsWidth {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44, alignment: .leading)
            .background(
                AppPalette.control.opacity(isDisabled ? 0.35 : 1),
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .accessibilityLabel("\(title)\(subtitle.map { ", \($0)" } ?? "")")
    }
}

private struct MaiaDataBoundaryStrip: View {
    let healthKitEnabled: Bool
    let pantryCount: Int

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppSpacing.row) {
                MaiaDataChip(icon: "calendar", text: "Today", color: AppPalette.brand)
                MaiaDataChip(icon: "target", text: "Goals", color: .accentPositive)
                if healthKitEnabled {
                    MaiaDataChip(icon: "applewatch", text: "HealthKit", color: AppPalette.recovery)
                }
                if pantryCount > 0 {
                    MaiaDataChip(icon: "cabinet.fill", text: "\(pantryCount) pantry", color: AppPalette.achievement)
                }
                MaiaDataChip(icon: "sparkles", text: "Estimates labeled", color: AppPalette.caution)
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("maia_evidence_strip")
    }
}

private struct MaiaDataChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .appFont(size: 9, weight: .bold)
                .foregroundStyle(color)
            Text(text)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct ChatBubble: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let message: ChatMessage
    let onLogRecipe: (String) -> Void
    let onSpeak: (String) -> Void
    let onStopSpeaking: () -> Void
    let currentSpokenText: String?
    let onAction: (MaiaAction) -> Void
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    private let canBeLogged: Bool
    private let spokenText: String

    init(
        message: ChatMessage,
        onLogRecipe: @escaping (String) -> Void,
        onSpeak: @escaping (String) -> Void,
        onStopSpeaking: @escaping () -> Void,
        currentSpokenText: String?,
        onAction: @escaping (MaiaAction) -> Void,
        showAlert: Binding<Bool>,
        alertMessage: Binding<String>
    ) {
        self.message = message
        self.onLogRecipe = onLogRecipe
        self.onSpeak = onSpeak
        self.onStopSpeaking = onStopSpeaking
        self.currentSpokenText = currentSpokenText
        self.onAction = onAction
        self._showAlert = showAlert
        self._alertMessage = alertMessage
        self.canBeLogged = !message.isUser && message.text.contains("---Nutritional Breakdown---") && message.text.contains("Calories:")
        self.spokenText = MaiaSpeechFormatter.spokenText(from: message.text)
    }

    private var isReadingThisResponse: Bool {
        currentSpokenText == spokenText && !spokenText.isEmpty
    }

    private var messageMaxWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? .infinity : 310
    }

    private struct ActionPayloadIssue: Identifiable {
        let id = UUID()
        let kind: String
    }

    private func parseStructuredPayloads(from text: String) -> (String, [MaiaActionPayload], [ActionPayloadIssue]) {
        var cleanText = text
        var payloads: [MaiaActionPayload] = []
        var issues: [ActionPayloadIssue] = []

        let pattern = "```json\\s*(\\{.*?\\})\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return (text, [], [ActionPayloadIssue(kind: "regex_failed")])
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches.reversed() {
            let jsonString = nsString.substring(with: match.range(at: 1))
            if let data = jsonString.data(using: .utf8) {
                do {
                    let payload = try JSONDecoder().decode(MaiaActionPayload.self, from: data)
                    payloads.append(payload)
                } catch {
                    issues.append(ActionPayloadIssue(kind: "decode_failed"))
                }
            } else {
                issues.append(ActionPayloadIssue(kind: "encoding_failed"))
            }
            cleanText = (cleanText as NSString).replacingCharacters(in: match.range, with: "")
        }

        return (cleanText.trimmingCharacters(in: .whitespacesAndNewlines), payloads.reversed(), issues)
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
                    let validationIssues = payloads.compactMap { payload -> ActionPayloadIssue? in
                        guard let issueKind = payload.validationIssueKind else { return nil }
                        return ActionPayloadIssue(kind: issueKind)
                    }
                    let payloadIssues = parsed.2 + validationIssues
                    let renderablePayloads = payloads.filter(\.isRenderableAction)

                    if !displayText.isEmpty {
                        Text(.init(displayText))
                            .appFont(size: 15)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(
                                message.isUser ? Color.brandPrimary.opacity(0.12) : AppPalette.control,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(
                                        message.isUser ? Color.brandPrimary.opacity(0.28) : AppPalette.separator,
                                        lineWidth: 1
                                    )
                            )
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: messageMaxWidth, alignment: message.isUser ? .trailing : .leading)
                    }

                    if !renderablePayloads.isEmpty && !message.isUser {
                        ForEach(renderablePayloads) { payload in
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
                                    .frame(maxWidth: messageMaxWidth, alignment: .leading)
                                }
                            } else if payload.type == "generate_meal_plan" {
                                AIChatMealPlanActionCard(onConfirm: {
                                    onAction(.generateMealPlan)
                                })
                                .frame(maxWidth: messageMaxWidth, alignment: .leading)
                            } else if payload.type == "log_workout" {
                                if let ex = payload.exerciseName, let d = payload.durationMinutes, let c = payload.caloriesBurned {
                                    AIChatWorkoutActionCard(exerciseName: ex, durationMinutes: d, caloriesBurned: c, onConfirm: {
                                        onAction(.logWorkout(exerciseName: ex, durationMinutes: d, caloriesBurned: c))
                                    })
                                    .frame(maxWidth: messageMaxWidth, alignment: .leading)
                                }
                            } else if payload.type == "log_water" {
                                if let oz = payload.amountOunces {
                                    AIChatWaterActionCard(amountOunces: oz, onConfirm: {
                                        onAction(.logWater(amountOunces: oz))
                                    })
                                    .frame(maxWidth: messageMaxWidth, alignment: .leading)
                                }
                            } else if payload.type == "start_fast" {
                                AIChatFastActionCard(fastHours: payload.fastHours, isStop: false, onConfirm: {
                                    onAction(.startFast(hours: payload.fastHours ?? 16))
                                })
                                .frame(maxWidth: messageMaxWidth, alignment: .leading)
                            } else if payload.type == "stop_fast" {
                                AIChatFastActionCard(fastHours: nil, isStop: true, onConfirm: {
                                    onAction(.stopFast)
                                })
                                .frame(maxWidth: messageMaxWidth, alignment: .leading)
                            } else if payload.type == "log_weight" {
                                if let w = payload.weightPounds {
                                    AIChatWeightActionCard(weightPounds: w, onConfirm: {
                                        onAction(.logWeight(weightPounds: w))
                                    })
                                    .frame(maxWidth: messageMaxWidth, alignment: .leading)
                                }
                            }
                        }
                    }

                    if !payloadIssues.isEmpty && !message.isUser {
                        MaiaActionParseFallbackCard(issueCount: payloadIssues.count)
                            .frame(maxWidth: messageMaxWidth, alignment: .leading)
                    }
                }

                if !message.isUser {
                    Spacer(minLength: 42)
                }
            }

            HStack(spacing: 12) {
                if message.isUser { Spacer() }
                if !message.isUser && !spokenText.isEmpty {
                    Button(action: {
                        if isReadingThisResponse {
                            onStopSpeaking()
                        } else {
                            onSpeak(spokenText)
                        }
                    }) {
                        Label(
                            isReadingThisResponse ? "Stop Reading" : "Read Aloud",
                            systemImage: isReadingThisResponse ? "stop.fill" : "speaker.wave.2.fill"
                        )
                        .appFont(size: 12, weight: .semibold)
                    }
                    .foregroundColor(.brandForeground)
                    .buttonStyle(.plain)
                    .accessibilityHint("Reads Maia's visible response using the selected voice.")
                }
                if canBeLogged {
                    Button(action: { onLogRecipe(message.text) }) {
                        Label("Log Food", systemImage: "plus.circle.fill")
                            .appFont(size: 12, weight: .semibold)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color.brandPrimary, in: Capsule())
                            .foregroundColor(AppPalette.onBrand)
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

private struct MaiaActionParseFallbackCard: View {
    let issueCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .appFont(size: 14, weight: .bold)
                .foregroundColor(AppPalette.caution)
                .frame(width: 28, height: 28)
                .background(AppPalette.caution.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Action needs retry")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text("Maia's answer is still shown, but the action button payload was incomplete.")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppPalette.caution.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppPalette.caution.opacity(0.16), lineWidth: 1)
        )
        .onAppear {
            DIContainer.shared.analyticsManager?.logEvent("maia_action_payload_failed", parameters: [
                "issue_count": issueCount
            ])
        }
    }
}

private struct AIChatActionHeader<Action: View>: View {
    let title: String
    let subtitle: String?
    private let action: Action

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                textBlock
                    .layoutPriority(1)
                Spacer(minLength: AppSpacing.compact)
                action
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                textBlock
                action
            }
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    @State private var didLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(title: mealName) {
                Button(action: {
                    guard !didLog else { return }
                    didLog = true
                    onLog()
                }) {
                    Text(didLog ? "Logged" : "Log Food")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didLog ? .accentPositive : AppPalette.onBrand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            didLog ? Color.accentPositive.opacity(0.12) : Color.brandPrimary,
                            in: Capsule()
                        )
                }
                .disabled(didLog)
                .buttonStyle(AnimatedCardButtonStyle())
            }

            Text(
                "\(Int(calories.rounded())) cal  ·  " +
                "\(Int(protein.rounded()))g protein  ·  " +
                "\(Int(carbs.rounded()))g carbs  ·  " +
                "\(Int(fats.rounded()))g fat"
            )
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("maia_action_meal")
    }
}

struct AIChatMealPlanActionCard: View {
    let onConfirm: () -> Void
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(
                title: "7-Day Meal Plan",
                subtitle: "Includes grocery list generation"
            ) {
                Button(action: {
                    didConfirm = true
                    onConfirm()
                }) {
                    Text(didConfirm ? "Generated" : "Generate")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didConfirm ? .accentPositive : AppPalette.onBrand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            didConfirm ? Color.accentPositive.opacity(0.12) : Color.brandPrimary,
                            in: Capsule()
                        )
                }
                .disabled(didConfirm)
                .buttonStyle(AnimatedCardButtonStyle())
            }
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("maia_action_meal_plan")
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
            AIChatActionHeader(title: exerciseName) {
                Button(action: {
                    didConfirm = true
                    onConfirm()
                }) {
                    Text(didConfirm ? "Logged" : "Log Workout")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didConfirm ? .accentPositive : AppPalette.onBrand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            didConfirm ? Color.accentPositive.opacity(0.12) : Color.brandPrimary,
                            in: Capsule()
                        )
                }
                .disabled(didConfirm)
                .buttonStyle(AnimatedCardButtonStyle())
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 128), spacing: AppSpacing.compact)],
                spacing: AppSpacing.compact
            ) {
                MacroLabel(title: "Time", value: "\(durationMinutes)m")
                MacroLabel(title: "Burn", value: "\(Int(caloriesBurned.rounded())) cal")
            }
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("maia_action_workout")
    }
}

struct AIChatWaterActionCard: View {
    let amountOunces: Double
    let onConfirm: () -> Void
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(title: "Log Water") {
                Button(action: {
                    didConfirm = true
                    onConfirm()
                }) {
                    Text(didConfirm ? "Logged" : "Confirm")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didConfirm ? .accentPositive : AppPalette.onBrand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            didConfirm ? Color.accentPositive.opacity(0.12) : Color.brandPrimary,
                            in: Capsule()
                        )
                }
                .disabled(didConfirm)
                .buttonStyle(AnimatedCardButtonStyle())
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 128), spacing: AppSpacing.compact)],
                spacing: AppSpacing.compact
            ) {
                MacroLabel(title: "Amount", value: "\(Int(amountOunces.rounded())) oz")
            }
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("maia_action_water")
    }
}

struct AIChatFastActionCard: View {
    let fastHours: Int?
    let isStop: Bool
    let onConfirm: () -> Void
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(title: isStop ? "End Fast" : "Start Fast") {
                Button(action: {
                    didConfirm = true
                    onConfirm()
                }) {
                    Text(didConfirm ? "Confirmed" : "Confirm")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didConfirm ? .accentPositive : AppPalette.onBrand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            didConfirm ? Color.accentPositive.opacity(0.12) : Color.brandPrimary,
                            in: Capsule()
                        )
                }
                .disabled(didConfirm)
                .buttonStyle(AnimatedCardButtonStyle())
            }

            if let hours = fastHours, !isStop {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 128), spacing: AppSpacing.compact)],
                    spacing: AppSpacing.compact
                ) {
                    MacroLabel(title: "Duration", value: "\(hours) hrs")
                }
            }
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("maia_action_fast")
    }
}

struct AIChatWeightActionCard: View {
    let weightPounds: Double
    let onConfirm: () -> Void
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(title: "Log Weight") {
                Button(action: {
                    didConfirm = true
                    onConfirm()
                }) {
                    Text(didConfirm ? "Logged" : "Confirm")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(didConfirm ? .accentPositive : AppPalette.onBrand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            didConfirm ? Color.accentPositive.opacity(0.12) : Color.brandPrimary,
                            in: Capsule()
                        )
                }
                .disabled(didConfirm)
                .buttonStyle(AnimatedCardButtonStyle())
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 128), spacing: AppSpacing.compact)],
                spacing: AppSpacing.compact
            ) {
                MacroLabel(
                    title: "Weight",
                    value: String(
                        format: "%.1f %@",
                        BodyUnits.weightDisplayValue(lbs: weightPounds, metric: useMetric),
                        BodyUnits.weightUnit(metric: useMetric)
                    )
                )
            }
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("maia_action_weight")
    }
}

struct MacroLabel: View {
    let title: String
    let value: String
    var color: Color = .textPrimary
    var bgColor: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(color == .white ? .white.opacity(0.8) : Color(UIColor.secondaryLabel))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(bgColor ?? AppPalette.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#if DEBUG
struct MaiaActionCardGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Maia",
                    title: "Action Cards",
                    subtitle: "Review the proposed change before anything is logged."
                )

                AIChatActionCard(
                    mealName: "Greek yogurt, berries, and oats",
                    calories: 430,
                    protein: 31,
                    carbs: 55,
                    fats: 9,
                    onLog: {}
                )

                AIChatMealPlanActionCard(onConfirm: {})

                AIChatWorkoutActionCard(
                    exerciseName: "Full-body strength session",
                    durationMinutes: 48,
                    caloriesBurned: 325,
                    onConfirm: {}
                )

                AIChatWaterActionCard(amountOunces: 16, onConfirm: {})
                AIChatFastActionCard(fastHours: 16, isStop: false, onConfirm: {})
                AIChatWeightActionCard(weightPounds: 184.6, onConfirm: {})
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .accessibilityIdentifier("maia_action_gallery")
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Maia Actions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

struct ChatHistoryListView<TopContent: View, BottomContent: View>: View {
    @Binding var chatMessages: [ChatMessage]
    var onLogRecipe: (String) -> Void
    var onSpeak: (String) -> Void
    var onStopSpeaking: () -> Void
    var currentSpokenText: String?
    var onAction: (MaiaAction) -> Void
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    let topContent: TopContent
    let bottomContent: BottomContent

    init(
        chatMessages: Binding<[ChatMessage]>,
        onLogRecipe: @escaping (String) -> Void,
        onSpeak: @escaping (String) -> Void,
        onStopSpeaking: @escaping () -> Void,
        currentSpokenText: String?,
        onAction: @escaping (MaiaAction) -> Void,
        showAlert: Binding<Bool>,
        alertMessage: Binding<String>,
        @ViewBuilder topContent: () -> TopContent,
        @ViewBuilder bottomContent: () -> BottomContent
    ) {
        _chatMessages = chatMessages
        self.onLogRecipe = onLogRecipe
        self.onSpeak = onSpeak
        self.onStopSpeaking = onStopSpeaking
        self.currentSpokenText = currentSpokenText
        self.onAction = onAction
        _showAlert = showAlert
        _alertMessage = alertMessage
        self.topContent = topContent()
        self.bottomContent = bottomContent()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topContent
                        .id("maia-conversation-top")

                    VStack(alignment: .leading, spacing: 10) {
                        if chatMessages.count > 1 {
                            ForEach(chatMessages) { message in
                                ChatBubble(
                                    message: message,
                                    onLogRecipe: onLogRecipe,
                                    onSpeak: onSpeak,
                                    onStopSpeaking: onStopSpeaking,
                                    currentSpokenText: currentSpokenText,
                                    onAction: onAction,
                                    showAlert: $showAlert,
                                    alertMessage: $alertMessage
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.row)

                    bottomContent
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chatMessages) {
                if chatMessages.count > 1, let lastId = chatMessages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo("maia-conversation-top", anchor: .top)
                }
            }
            .onAppear {
                if chatMessages.count > 1, let lastId = chatMessages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                } else {
                    proxy.scrollTo("maia-conversation-top", anchor: .top)
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

    private var contextSummary: String {
        let mealText = mealCount == 1 ? "1 meal" : "\(mealCount) meals"
        let workoutText = workoutCount == 1 ? "1 workout" : "\(workoutCount) workouts"
        let waterText = "\(Int(water.rounded()).formatted()) of \(Int(waterGoal.rounded()).formatted()) oz water"
        return [mealText, workoutText, waterText].joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Today in context", subtitle: contextSummary)

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Calories left",
                    value: Int(calories.rounded()).formatted(),
                    accent: AppPalette.energy
                ),
                AppMetricItem(
                    label: "Protein left",
                    value: "\(Int(protein.rounded()).formatted())g",
                    accent: .accentProtein
                ),
                AppMetricItem(
                    label: "Carbs left",
                    value: "\(Int(carbs.rounded()).formatted())g",
                    accent: .accentCarbs
                ),
                AppMetricItem(
                    label: "Fats left",
                    value: "\(Int(fats.rounded()).formatted())g",
                    accent: .accentFats
                )
            ])
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("maia_daily_context")
    }
}

struct MaiaHealthKitContextIndicator: View {
    let steps: Double
    let activeEnergy: Double
    let sleepSummary: SleepHealthSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var healthSummary: String {
        let sleepHours = sleepSummary.lastNightHours
        let sleepScore = sleepSummary.lastNightScore ?? sleepSummary.averageScore
        var parts: [String] = []

        if steps > 0 { parts.append("\(Int(steps.rounded()).formatted()) steps") }
        if activeEnergy > 0 { parts.append("\(Int(activeEnergy.rounded()).formatted()) active cal") }
        if sleepHours > 0 { parts.append(String(format: "%.1f hr sleep", sleepHours)) }
        if let sleepScore { parts.append("sleep score \(sleepScore)") }

        return parts.isEmpty ? "No recent metrics" : parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    healthLabel
                    healthSummaryText
                }
            } else {
                HStack(spacing: AppSpacing.compact) {
                    healthLabel
                    Spacer(minLength: AppSpacing.row)
                    healthSummaryText
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("maia_health_context")
    }

    private var healthLabel: some View {
        Label("Apple Health included", systemImage: "applewatch")
            .appTextRole(.caption)
            .foregroundStyle(AppPalette.brandText)
    }

    private var healthSummaryText: some View {
        Text(healthSummary)
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
