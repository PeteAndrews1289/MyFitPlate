import MyFitPlateCore

import SwiftUI

struct MaiaActionBoardView: View {
    let remainingCalories: Double
    let remainingProtein: Double
    let waterRemaining: Double
    let hasWorkoutToday: Bool
    let hasNutritionMismatch: Bool
    let healthKitEnabled: Bool
    let pantryCount: Int
    let isGeneratingMeal: Bool
    var waterUnit: WaterVolumeUnit = .ounces
    var waterTrackingOnly = false
    var onFillMacros: () -> Void
    var onProteinOrRecovery: () -> Void
    var onTrustOrToday: () -> Void
    var onHydrate: () -> Void

    private enum ActionKind: String, CaseIterable, Identifiable {
        case fillMacros
        case proteinOrRecovery
        case trustOrToday
        case hydrate

        var id: String { rawValue }
    }

    private var proteinCardTitle: String {
        hasWorkoutToday ? "Plan a recovery meal" : "Find a high-protein meal"
    }

    private var proteinCardSubtitle: String? {
        if hasWorkoutToday {
            return "\(Int(remainingProtein.rounded())) g left"
        }
        return remainingProtein >= 15 ? "\(Int(remainingProtein.rounded())) g left" : nil
    }

    private var trustCardTitle: String {
        hasNutritionMismatch ? "Check food estimates" : "Review my day"
    }

    private var recommendedAction: ActionKind {
        if hasNutritionMismatch { return .trustOrToday }
        if hasWorkoutToday && remainingProtein >= 10 { return .proteinOrRecovery }
        if remainingCalories >= 150 { return .fillMacros }
        if !waterTrackingOnly && waterRemaining > 0 { return .hydrate }
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
                        Text(recommendedAction == .hydrate ? "Log " + waterAmount(16) + " of water" : title(for: recommendedAction))
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
                .appSurface(.interpreted, radius: AppRadius.hero)
            }
            .buttonStyle(.plain)
            .disabled(recommendedAction == .fillMacros && isGeneratingMeal)
            .accessibilityIdentifier("maia_recommended_action")

            VStack(spacing: 0) {
                ForEach(secondaryActions) { action in
                    if action != secondaryActions.first { Divider().padding(.leading, 48) }
                    secondaryActionRow(action)
                }
            }
            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))

            MaiaDataBoundaryStrip(healthKitEnabled: healthKitEnabled, pantryCount: pantryCount)

        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func title(for action: ActionKind) -> String {
        switch action {
        case .fillMacros: "Find a meal for my macros"
        case .proteinOrRecovery: proteinCardTitle
        case .trustOrToday: trustCardTitle
        case .hydrate: "Log water"
        }
    }

    private func subtitle(for action: ActionKind) -> String? {
        switch action {
        case .fillMacros: "\(Int(remainingCalories.rounded())) cal"
        case .proteinOrRecovery: proteinCardSubtitle
        case .trustOrToday: nil
        case .hydrate: waterAmount(16)
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
                ? "You trained today and have \(Int(remainingProtein.rounded()).formatted()) g protein left."
                : "You have \(Int(remainingProtein.rounded()).formatted()) g protein left today."
        case .trustOrToday:
            hasNutritionMismatch
                ? "A nutrition mismatch is worth reviewing before you use today's totals."
                : "See what today's food, water, and training point to."
        case .hydrate:
            "Log " + waterAmount(16) + " of water. " + (waterTrackingOnly
                ? "You are tracking without a daily target."
                : waterAmount(max(0, waterRemaining)) + " remains toward today's target.")
        }
    }

    private func waterAmount(_ ounces: Double) -> String {
        "\(waterUnit.amount(fromOunces: ounces).formatted(.number.precision(.fractionLength(0...1)))) \(waterUnit.symbol)"
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
        case .hydrate: !waterTrackingOnly && waterRemaining <= 0
        case .proteinOrRecovery, .trustOrToday: false
        }
    }

    private func secondaryActionRow(_ action: ActionKind) -> some View {
        Button { perform(action) } label: {
            HStack(spacing: AppSpacing.row) {
                if action == .fillMacros && isGeneratingMeal {
                    ProgressView().frame(width: 24)
                } else {
                    Image(systemName: icon(for: action)).foregroundStyle(tint(for: action)).frame(width: 24)
                }
                Text(title(for: action)).appTextRole(.control).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let detail = subtitle(for: action) {
                    Text(detail).appTextRole(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, AppSpacing.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled(action))
        .accessibilityIdentifier("maia_shortcut_" + action.rawValue)
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
                    MaiaDataChip(icon: "applewatch", text: "Apple Health", color: AppPalette.recovery)
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
    @EnvironmentObject private var goalSettings: GoalSettings

    let message: ChatMessage
    let onLogRecipe: (String, String, @escaping (Bool) -> Void) -> Void
    let onSpeak: (String) -> Void
    let onStopSpeaking: () -> Void
    let currentSpokenText: String?
    let onAction: (MaiaAction, String, @escaping (Bool) -> Void) -> Void
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    private let canBeLogged: Bool
    private let spokenText: String

    init(
        message: ChatMessage,
        onLogRecipe: @escaping (String, String, @escaping (Bool) -> Void) -> Void,
        onSpeak: @escaping (String) -> Void,
        onStopSpeaking: @escaping () -> Void,
        currentSpokenText: String?,
        onAction: @escaping (MaiaAction, String, @escaping (Bool) -> Void) -> Void,
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

    private struct PositionedAction: Identifiable {
        let index: Int
        let payload: MaiaActionPayload
        var id: Int { index }
    }

    private func frozenWeight(actionID: String) -> Double? {
        guard let receipt = MaiaActionSaveSession.savedReceipt(userID: DIContainer.shared.authService.currentUserID, actionID: actionID),
              case .weight(let pounds)? = receipt.command else { return nil }
        return pounds
    }

    private func parseStructuredPayloads(from text: String) -> (String, [PositionedAction], [ActionPayloadIssue]) {
        var cleanText = text
        var payloads: [PositionedAction] = []
        var issues: [ActionPayloadIssue] = []

        let pattern = "```json\\s*(\\{.*?\\})\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return (text, [], [ActionPayloadIssue(kind: "regex_failed")])
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        for (index, match) in matches.enumerated().reversed() {
            let jsonString = nsString.substring(with: match.range(at: 1))
            if let data = jsonString.data(using: .utf8) {
                do {
                    let payload = try JSONDecoder().decode(MaiaActionPayload.self, from: data)
                    payloads.append(PositionedAction(index: index, payload: payload))
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
                    let validationIssues = payloads.compactMap { positioned -> ActionPayloadIssue? in
                        guard let issueKind = positioned.payload.validationIssueKind else { return nil }
                        return ActionPayloadIssue(kind: issueKind)
                    }
                    let payloadIssues = parsed.2 + validationIssues
                    let renderablePayloads = payloads.filter { $0.payload.isRenderableAction }

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
                        ForEach(renderablePayloads) { positioned in
                            let payload = positioned.payload
                            let actionID = "\(message.id.uuidString)-action-\(positioned.index)"
                            if payload.type == "meal_suggestion" || payload.type == nil {
                                if let name = payload.mealName, let c = payload.calories, let p = payload.protein, let cb = payload.carbs, let f = payload.fats {
                                    AIChatActionCard(mealName: name, calories: c, protein: p, carbs: cb, fats: f, actionID: actionID, onLog: { completion in
                                        let legacyFormat = """
                                        \(name)
                                        ---Nutritional Breakdown---
                                        Calories: \(c)
                                        Protein: \(p)g
                                        Carbs: \(cb)g
                                        Fats: \(f)g
                                        """
                                        onLogRecipe(legacyFormat, actionID, completion)
                                    })
                                    .frame(maxWidth: messageMaxWidth, alignment: .leading)
                                }
                            } else if payload.type == "generate_meal_plan" {
                                AIChatMealPlanActionCard(onConfirm: { completion in
                                    onAction(.generateMealPlan, actionID, completion)
                                })
                                .frame(maxWidth: messageMaxWidth, alignment: .leading)
                            } else if payload.type == "log_workout" {
                                if let ex = payload.exerciseName, let d = payload.durationMinutes, let c = payload.caloriesBurned {
                                    AIChatWorkoutActionCard(exerciseName: ex, durationMinutes: d, caloriesBurned: c, actionID: actionID, onConfirm: { completion in
                                        onAction(.logWorkout(exerciseName: ex, durationMinutes: d, caloriesBurned: c), actionID, completion)
                                    })
                                    .frame(maxWidth: messageMaxWidth, alignment: .leading)
                                }
                            } else if payload.type == "log_water" {
                                if let oz = payload.amountOunces {
                                    AIChatWaterActionCard(amountOunces: oz, actionID: actionID, waterUnit: goalSettings.hydrationPreferences.unit, onConfirm: { completion in
                                        onAction(.logWater(amountOunces: oz), actionID, completion)
                                    })
                                    .frame(maxWidth: messageMaxWidth, alignment: .leading)
                                }
                            } else if payload.type == "start_fast" {
                                AIChatFastActionCard(fastHours: payload.fastHours, isStop: false, actionID: actionID, onConfirm: { completion in
                                    onAction(.startFast(hours: payload.fastHours ?? 16), actionID, completion)
                                })
                                .frame(maxWidth: messageMaxWidth, alignment: .leading)
                            } else if payload.type == "stop_fast" {
                                AIChatFastActionCard(fastHours: nil, isStop: true, actionID: actionID, onConfirm: { completion in
                                    onAction(.stopFast, actionID, completion)
                                })
                                .frame(maxWidth: messageMaxWidth, alignment: .leading)
                            } else if payload.type == "log_weight" {
                                if let w = payload.weightPounds {
                                    let shownWeight = frozenWeight(actionID: actionID) ?? w
                                    AIChatWeightActionCard(weightPounds: shownWeight, actionID: actionID, onConfirm: { completion in
                                        onAction(.logWeight(weightPounds: shownWeight), actionID, completion)
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
                    MaiaConfirmedActionButton(title: "Log food", savedTitle: "Logged", identifier: "maia_legacy_log", actionID: "\(message.id.uuidString)-legacy-meal") {
                        onLogRecipe(message.text, "\(message.id.uuidString)-legacy-meal", $0)
                    }
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
                Text("This action is not ready")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text("The suggested action was incomplete. Ask Maia to prepare it again; the rest of the answer is still available.")
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

private struct MaiaConfirmedActionButton: View {
    let title: String
    let savedTitle: String
    let identifier: String
    var actionID: String?
    let action: (@escaping (Bool) -> Void) -> Void
    @State private var isSaving = false
    @State private var isSaved = false

    var body: some View {
        Button {
            guard !isSaving, !isSaved else { return }
            isSaving = true
            action { accepted in
                isSaving = false
                isSaved = accepted
            }
        } label: {
            HStack(spacing: AppSpacing.compact) {
                if isSaving { ProgressView().controlSize(.small) }
                Text(isSaving ? "Saving…" : isSaved ? savedTitle : title)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appTextRole(.control)
            .frame(minHeight: 44)
        }
        .disabled(isSaving || isSaved)
        .buttonStyle(.bordered)
        .accessibilityIdentifier(identifier)
        .onAppear(perform: restoreSavedReceipt)
        .onChange(of: actionID) { _, _ in restoreSavedReceipt() }
        .onReceive(NotificationCenter.default.publisher(for: MaiaActionSaveSession.receiptDidChange)) { notification in
            if notification.userInfo?["actionID"] as? String == actionID { restoreSavedReceipt() }
        }
    }

    private func restoreSavedReceipt() {
        isSaved = MaiaActionSaveSession.savedReceipt(userID: DIContainer.shared.authService.currentUserID, actionID: actionID)?.isAccepted == true
    }
}

struct MaiaRetainedActionsView: View {
    let receipts: [MaiaSavedActionReceipt]
    let isSaving: Bool
    let onRetry: (MaiaSavedActionReceipt) -> Void

    var body: some View {
        DisclosureGroup("\(receipts.count) kept Maia actions") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Submitted saves may already be logged. Retrying uses each original entry and date to avoid a duplicate. Clearing chat does not cancel them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(receipts, id: \.actionID) { receipt in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(receipt.actionDescription).font(.subheadline)
                            Text("\(receipt.hasBeenSubmitted ? "Submitted or unconfirmed" : "Not submitted") · \(receipt.destinationDescription)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(receipt.hasBeenSubmitted ? "Retry" : "Save") { onRetry(receipt) }
                            .disabled(isSaving)
                            .accessibilityIdentifier("maia_retained_action_retry")
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(12)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("maia_retained_actions")
    }
}

private struct MaiaActionReceiptHint: View {
    let actionID: String?
    @State private var receipt: MaiaSavedActionReceipt?

    var body: some View {
        Group {
            if let receipt {
                Text("\(receipt.isAccepted ? "Saved" : "Pending") · \(receipt.destinationDescription)")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("maia_action_receipt")
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: MaiaActionSaveSession.receiptDidChange)) { notification in
            if notification.userInfo?["actionID"] as? String == actionID { reload() }
        }
    }

    private func reload() {
        receipt = MaiaActionSaveSession.savedReceipt(userID: DIContainer.shared.authService.currentUserID, actionID: actionID)
    }
}

struct AIChatActionCard: View {
    let mealName: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    var actionID: String?
    let onLog: (@escaping (Bool) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(title: mealName) {
                MaiaConfirmedActionButton(
                    title: "Log food", savedTitle: "Logged", identifier: "maia_meal_log", actionID: actionID, action: onLog
                )
            }

            Text(
                "\(calories.formatted(.number.precision(.fractionLength(0)))) cal  ·  " +
                "\(protein.formatted(.number.precision(.fractionLength(0))))g protein  ·  " +
                "\(carbs.formatted(.number.precision(.fractionLength(0))))g carbs  ·  " +
                "\(fats.formatted(.number.precision(.fractionLength(0))))g fat"
            )
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            MaiaActionReceiptHint(actionID: actionID)
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maia_action_meal")
    }
}

struct AIChatMealPlanActionCard: View {
    let onConfirm: (@escaping (Bool) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(
                title: "Plan your week",
                subtitle: "Choose preferences and review before saving"
            ) {
                MaiaConfirmedActionButton(
                    title: "Plan week", savedTitle: "Opened", identifier: "maia_plan_generate", action: onConfirm
                )
            }
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("maia_action_meal_plan")
    }
}

struct AIChatWorkoutActionCard: View {
    let exerciseName: String
    let durationMinutes: Int
    let caloriesBurned: Double
    var actionID: String?
    let onConfirm: (@escaping (Bool) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(title: exerciseName) {
                MaiaConfirmedActionButton(
                    title: "Log workout", savedTitle: "Logged", identifier: "maia_workout_log", actionID: actionID, action: onConfirm
                )
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 128), spacing: AppSpacing.compact)],
                spacing: AppSpacing.compact
            ) {
                MacroLabel(title: "Time", value: "\(durationMinutes)m")
                MacroLabel(title: "Burn", value: "\(caloriesBurned.formatted(.number.precision(.fractionLength(0)))) cal")
            }
            MaiaActionReceiptHint(actionID: actionID)
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("maia_action_workout")
    }
}

struct AIChatWaterActionCard: View {
    let amountOunces: Double
    var actionID: String?
    var waterUnit: WaterVolumeUnit = .ounces
    let onConfirm: (@escaping (Bool) -> Void) -> Void

    private var amountText: String {
        "\(waterUnit.amount(fromOunces: amountOunces).formatted(.number.precision(.fractionLength(0...1)))) \(waterUnit.symbol)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(title: "Water") {
                MaiaConfirmedActionButton(
                    title: "Add " + amountText, savedTitle: "Logged", identifier: "maia_water_log", actionID: actionID, action: onConfirm
                )
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 128), spacing: AppSpacing.compact)],
                spacing: AppSpacing.compact
            ) {
                MacroLabel(title: "Amount", value: amountText)
            }
            MaiaActionReceiptHint(actionID: actionID)
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("maia_action_water")
    }
}

struct AIChatFastActionCard: View {
    let fastHours: Int?
    let isStop: Bool
    var actionID: String?
    let onConfirm: (@escaping (Bool) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(title: isStop ? "End Fast" : "Start Fast") {
                MaiaConfirmedActionButton(
                    title: "Confirm", savedTitle: "Confirmed", identifier: "maia_fast_confirm", actionID: actionID, action: onConfirm
                )
            }

            if let hours = fastHours, !isStop {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 128), spacing: AppSpacing.compact)],
                    spacing: AppSpacing.compact
                ) {
                    MacroLabel(title: "Duration", value: "\(hours) hrs")
                }
            }
            MaiaActionReceiptHint(actionID: actionID)
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("maia_action_fast")
    }
}

struct AIChatWeightActionCard: View {
    let weightPounds: Double
    var actionID: String?
    let onConfirm: (@escaping (Bool) -> Void) -> Void
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatActionHeader(title: "Log Weight") {
                MaiaConfirmedActionButton(
                    title: "Confirm", savedTitle: "Logged", identifier: "maia_weight_log", actionID: actionID, action: onConfirm
                )
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
            MaiaActionReceiptHint(actionID: actionID)
        }
        .appSurface(.quiet)
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
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var goalSettings: GoalSettings
    @StateObject private var viewModel = AIChatbotViewModel()

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
                    onLog: { completion in
                        viewModel.logRecipe(recipeText: """
                        Greek yogurt, berries, and oats
                        ---Nutritional Breakdown---
                        Calories: 430
                        Protein: 31g
                        Carbs: 55g
                        Fats: 9g
                        """, completion: completion)
                    }
                )

                AIChatMealPlanActionCard(onConfirm: { $0(true) })

                AIChatWorkoutActionCard(
                    exerciseName: "Full-body strength session",
                    durationMinutes: 48,
                    caloriesBurned: 325,
                    onConfirm: { $0(true) }
                )

                AIChatWaterActionCard(amountOunces: 16, onConfirm: { $0(true) })
                AIChatFastActionCard(fastHours: 16, isStop: false, onConfirm: { $0(true) })
                AIChatWeightActionCard(weightPounds: 184.6, onConfirm: { $0(true) })
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .accessibilityIdentifier("maia_action_gallery")
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Maia Actions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.dailyLogService = dailyLogService
            viewModel.goalSettings = goalSettings
        }
        .alert("Maia", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
    }
}
#endif

struct ChatHistoryListView<TopContent: View, BottomContent: View>: View {
    @Binding var chatMessages: [ChatMessage]
    var onLogRecipe: (String, String, @escaping (Bool) -> Void) -> Void
    var onSpeak: (String) -> Void
    var onStopSpeaking: () -> Void
    var currentSpokenText: String?
    var onAction: (MaiaAction, String, @escaping (Bool) -> Void) -> Void
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    let topContent: TopContent
    let bottomContent: BottomContent

    init(
        chatMessages: Binding<[ChatMessage]>,
        onLogRecipe: @escaping (String, String, @escaping (Bool) -> Void) -> Void,
        onSpeak: @escaping (String) -> Void,
        onStopSpeaking: @escaping () -> Void,
        currentSpokenText: String?,
        onAction: @escaping (MaiaAction, String, @escaping (Bool) -> Void) -> Void,
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
    var waterUnit: WaterVolumeUnit = .ounces
    var waterTrackingOnly = false
    @State private var showsDetails = false

    private var contextSummary: String {
        let mealText = mealCount == 1 ? "1 meal" : "\(mealCount) meals"
        let workoutText = workoutCount == 1 ? "1 workout" : "\(workoutCount) workouts"
        let amount = waterUnit.amount(fromOunces: water).formatted(.number.precision(.fractionLength(0...1)))
        let target = waterUnit.amount(fromOunces: waterGoal).formatted(.number.precision(.fractionLength(0...1)))
        let waterText = waterTrackingOnly ? "\(amount) \(waterUnit.symbol) water · tracking only" : "\(amount) of \(target) \(waterUnit.symbol) water"
        return [mealText, workoutText, waterText].joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("\(Int(abs(calories).rounded()).formatted()) cal \(calories >= 0 ? "left" : "over") · \(Int(max(0, protein).rounded()).formatted()) g protein left")
                .appTextRole(.control).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Today's context", isExpanded: $showsDetails) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(contextSummary)
                    Text("\(Int(max(0, carbs).rounded()).formatted()) g carbs · \(Int(max(0, fats).rounded()).formatted()) g fat remaining")
                }
                .appTextRole(.secondary).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppSpacing.compact)
            }
            .appTextRole(.secondary)
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
    var label: String?
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: AppSpacing.compact) {
            HStack(spacing: 5) {
                DotView(isAnimating: $isAnimating, delay: 0.0)
                DotView(isAnimating: $isAnimating, delay: 0.2)
                DotView(isAnimating: $isAnimating, delay: 0.4)
            }

            if let label {
                Text(label)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Maia is responding")
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
