import MyFitPlateCore

import SwiftUI

struct AIChatbotView: View {
    @Binding var selectedTab: Int
    var chatContext: String?
    @Binding var isComposing: Bool

    @StateObject private var viewModel = AIChatbotViewModel()

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var pantryService: PantryService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @StateObject private var ttsManager = TTSManager.shared
    @State private var mealSuggestionReview: MealReviewSaveSession?
    @State private var mealSuggestion: MealSuggestion?
    @State private var showingSuggestionDetail = false
    @State private var isRegeneratingSuggestion = false
    @State private var showingFoodPreferences = false
    @FocusState private var isInputFocused: Bool

    private var hasNutritionMismatch: Bool {
        dailyLogService.currentDailyLog?.calorieConsistencyStatus().hasMeaningfulMismatch == true
    }

    private var canSendMessage: Bool {
        !viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.canStartNewRequest
    }

    private var canIncludeHealthContext: Bool {
        guard let userID = DIContainer.shared.authService.currentUserID,
              healthKitViewModel.hasSyncedHealthData else { return false }
        return AIDataConsentStore.shared.allowsHealthData(for: userID)
    }

    private var proteinOrRecoveryPrompt: String {
        if viewModel.workoutCount > 0 {
            return "Build a post-workout meal for today. Keep it close to my remaining calories and protein, explain the macro target, and return a loggable meal card if you suggest one."
        }
        if viewModel.remainingProtein >= 15 {
            return "Help me hit \(Int(viewModel.remainingProtein.rounded()))g more protein today. Give me one practical option and return a loggable meal card if it fits."
        }
        return "Give me one simple next meal idea that keeps today on track. Return a loggable meal card if it fits."
    }

    private var trustOrTodayPrompt: String {
        if hasNutritionMismatch {
            return "Audit today's calorie and macro mismatch. Tell me what to review first, what looks trustworthy, and what action I should take next."
        }
        return "Give me a quick read on today's logged food, water, training, and remaining macros. Keep it action-oriented."
    }

    static let maiaTourSteps: [SpotlightTourStep] = [
        SpotlightTourStep(id: "maia-actions", title: "Quick Actions",
                          text: "Tap a card and Maia builds it — fill your remaining macros, get a protein idea, or read your day."),
        SpotlightTourStep(id: "maia-composer", title: "Ask Maia anything",
                          text: "Type a question about food, workouts, or your goals. She already knows today's numbers.")
    ]

    private var conversationTitle: some View {
        Text(viewModel.currentConversation?.title ?? "Your daily coach")
            .appTextRole(.caption).foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        SpotlightTourScaffold(steps: AIChatbotView.maiaTourSteps) { isActive in
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.compact) {
                Image("maia_avatar")
                    .resizable().scaledToFit().frame(width: 36, height: 36)
                    .clipShape(Circle()).background(AppPalette.control, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maia").appTextRole(.sectionTitle)
                        .accessibilityIdentifier("maia_screen_header")
                    if !dynamicTypeSize.isAccessibilitySize { conversationTitle }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { viewModel.showingConversations = true } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .buttonStyle(AppIconButtonStyle(.neutral))
                .accessibilityLabel("Conversations").accessibilityIdentifier("maia_conversations")
                Button { viewModel.showingContextControls = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(AppIconButtonStyle(.neutral))
                .accessibilityLabel("Context and style").accessibilityIdentifier("maia_context_controls")
                Menu {
                    NavigationLink {
                        ToolDirectoryView()
                    } label: { Label("Tools", systemImage: "square.grid.2x2") }
                    .accessibilityIdentifier("maia_personal_tools")
                    Button { showingFoodPreferences = true } label: {
                        Label("Food preferences", systemImage: "fork.knife")
                    }
                    .accessibilityIdentifier("maia_food_preferences")
                    if viewModel.chatMessages.count > 1 || !viewModel.retainedMaiaActions.isEmpty {
                        Button("Clear chat", systemImage: "trash", role: .destructive) { viewModel.reviewClearChat() }
                    }
                } label: { Image(systemName: "ellipsis") }
                .buttonStyle(AppIconButtonStyle(.neutral))
                .accessibilityLabel("More Maia options").accessibilityIdentifier("maia_more_options")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.compact)
            if dynamicTypeSize.isAccessibilitySize {
                conversationTitle.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
            }

            ChatHistoryListView(
                chatMessages: $viewModel.chatMessages,
                onLogRecipe: { viewModel.logRecipe(recipeText: $0, actionID: $1, completion: $2) },
                onSpeak: ttsManager.speak,
                onStopSpeaking: ttsManager.stopSpeaking,
                currentSpokenText: ttsManager.currentSpokenText,
                onAction: { viewModel.handleMaiaAction($0, actionID: $1, completion: $2) },
                showAlert: $viewModel.showAlert,
                alertMessage: $viewModel.alertMessage,
                topContent: {
                    VStack(spacing: 0) {
                        if let error = viewModel.storageError {
                            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                Text(error).appTextRole(.secondary)
                                Button(viewModel.hasConversationConflict ? "Keep both versions" : "Retry saving", action: viewModel.retryConversationStorage)
                            }.padding(AppSpacing.row).accessibilityIdentifier("maia_conversation_storage_error")
                        }
                        if !viewModel.retainedMaiaActions.isEmpty {
                            MaiaRetainedActionsView(receipts: viewModel.retainedMaiaActions, isSaving: viewModel.isSavingAction,
                                                    onRetry: viewModel.retryRetainedMaiaAction)
                                .padding(.horizontal, AppSpacing.screenHorizontal)
                                .padding(.top, AppSpacing.compact)
                        }
                        if viewModel.chatMessages.count <= 1 {
                            MaiaBriefingCard(
                                calories: viewModel.remainingCalories,
                                protein: viewModel.remainingProtein,
                                carbs: viewModel.remainingCarbs,
                                fats: viewModel.remainingFats,
                                water: viewModel.waterOunces,
                                waterGoal: viewModel.waterGoal,
                                mealCount: viewModel.mealCount,
                                workoutCount: viewModel.workoutCount,
                                waterUnit: goalSettings.hydrationPreferences.unit,
                                waterTrackingOnly: goalSettings.isWaterTrackingOnly
                            )
                            .padding(.horizontal, AppSpacing.screenHorizontal)
                            .padding(.top, AppSpacing.group)

                            if canIncludeHealthContext {
                                MaiaHealthKitContextIndicator(
                                    steps: healthKitViewModel.todaySteps,
                                    activeEnergy: healthKitViewModel.todayActiveEnergy,
                                    sleepSummary: healthKitViewModel.sleepSummary
                                )
                                .padding(.horizontal, AppSpacing.screenHorizontal)
                                .padding(.top, AppSpacing.compact)
                            }
                        }
                    }
                },
                bottomContent: {
                    VStack(spacing: 0) {
                        if let message = viewModel.inlineErrorMessage {
                            MaiaInlineFailureView(
                                message: message,
                                onRetry: viewModel.retryLastMessage
                            )
                            .padding(.horizontal, AppSpacing.screenHorizontal)
                            .padding(.vertical, AppSpacing.compact)
                        }

                        // Keep the action board available after prior chats whenever the composer is idle.
                        if viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                            !viewModel.isLoading &&
                            viewModel.inlineErrorMessage == nil &&
                            !isInputFocused {
                            MaiaActionBoardView(
                                remainingCalories: viewModel.remainingCalories,
                                remainingProtein: viewModel.remainingProtein,
                                waterRemaining: max(0, viewModel.waterGoal - viewModel.waterOunces),
                                hasWorkoutToday: viewModel.workoutCount > 0,
                                hasNutritionMismatch: hasNutritionMismatch,
                                healthKitEnabled: canIncludeHealthContext,
                                pantryCount: pantryService.pantryItems.count,
                                isGeneratingMeal: insightsService.isGeneratingSuggestion,
                                waterUnit: goalSettings.hydrationPreferences.unit,
                                waterTrackingOnly: goalSettings.isWaterTrackingOnly,
                                onFillMacros: generateMealSuggestionFromActionBoard,
                                onProteinOrRecovery: {
                                    let contract = viewModel.workoutCount > 0
                                        ? MaiaContextContract.recoveryMeal
                                        : MaiaContextContract.proteinAnchor
                                    sendActionPrompt(proteinOrRecoveryPrompt, contract: contract)
                                },
                                onTrustOrToday: {
                                    let contract = hasNutritionMismatch
                                        ? MaiaContextContract.trustAudit
                                        : MaiaContextContract.dailyRead(includeHealthKit: canIncludeHealthContext)
                                    sendActionPrompt(trustOrTodayPrompt, contract: contract)
                                },
                                onHydrate: {
                                    handleHydrationAction()
                                }
                            )
                            .padding(.horizontal, AppSpacing.screenHorizontal)
                            .padding(.vertical, AppSpacing.compact)
                            .featureSpotlight(isActive: isActive("maia-actions"))
                        }

                        if viewModel.isLoading {
                            HStack(alignment: .bottom, spacing: 10) {
                                Image("maia_avatar")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 34, height: 34)
                                    .clipShape(Circle())
                                    .background(Color.backgroundSecondary, in: Circle())

                                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                    MaiaTypingIndicator(label: viewModel.requestStage)
                                    if !viewModel.partialResponse.isEmpty {
                                        Text(MaiaSpeechFormatter.spokenText(from: String(viewModel.partialResponse.components(separatedBy: "```").first ?? "")))
                                            .appTextRole(.secondary).accessibilityIdentifier("maia_partial_response")
                                        Text("Draft response · actions appear after it finishes")
                                            .appTextRole(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()

                            }
                            .padding(.horizontal, AppSpacing.screenHorizontal)
                            .padding(.vertical, AppSpacing.compact)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
            )
            .onTapGesture { isInputFocused = false; hideKeyboard() }

            if ttsManager.playbackState != .idle { MaiaPlaybackControls(speech: ttsManager) }

            HStack(spacing: 10) {
                if isInputFocused {
                    Button {
                        isInputFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .buttonStyle(AppIconButtonStyle(.plain))
                    .accessibilityLabel("Dismiss keyboard")
                    .accessibilityIdentifier("maia_close_keyboard")
                }
                TextField("Ask Maia anything", text: $viewModel.userMessage, axis: .vertical)
                    .focused($isInputFocused)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.leading, isInputFocused ? 0 : AppSpacing.row)
                    .padding(.vertical, AppSpacing.row)
                    .lineLimit(1...4)
                    .onSubmit { viewModel.sendMessage() }
                    .accessibilityIdentifier("maia_message_input")

                if viewModel.isLoading {
                    Button(action: viewModel.cancelRequest) { Image(systemName: "stop.fill") }
                        .buttonStyle(AppIconButtonStyle(.neutral))
                        .accessibilityLabel("Cancel response").accessibilityIdentifier("maia_cancel_request")
                } else {
                    Button(action: { viewModel.sendMessage() }) { Image(systemName: "arrow.up") }
                        .buttonStyle(AppIconButtonStyle(.brand))
                        .disabled(!canSendMessage)
                        .opacity(canSendMessage ? 1 : 0.45)
                        .accessibilityLabel("Send message")
                }
            }
            .padding(4)
            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.hero))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.hero)
                    .strokeBorder(isInputFocused ? AppPalette.brandText : AppPalette.separator, lineWidth: isInputFocused ? 1 : 0.5)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.compact)
            .padding(.bottom, AppSpacing.compact)
            .background(
                Rectangle()
                    .fill(AppPalette.surface)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(
                        Rectangle().frame(height: 1).foregroundStyle(AppPalette.separator),
                        alignment: .top
                    )
            )
            .featureSpotlight(isActive: isActive("maia-composer"))
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: isInputFocused) { _, focused in isComposing = focused }
        .onAppear {
            viewModel.chatContext = self.chatContext
            viewModel.dailyLogService = self.dailyLogService
            viewModel.goalSettings = self.goalSettings
            viewModel.achievementService = self.achievementService
            viewModel.mealPlannerService = self.mealPlannerService
            viewModel.healthKitViewModel = self.healthKitViewModel
            viewModel.setupView()
            #if DEBUG
            if ScreenshotDemoMode.isEnabled {
                viewModel.showingContextControls = ScreenshotDemoData.requestedScreen == "design-maia-context"
                viewModel.showingConversations = ScreenshotDemoData.requestedScreen == "design-maia-topics"
            }
            if ScreenshotDemoMode.isEnabled, DIContainer.shared.authService.currentUserID == "mock_user",
               ProcessInfo.processInfo.arguments.contains("-ui-testing-maia-playback") {
                let bookmark = MaiaSpeechBookmark(plan: .init(source: "Use 42.5 lb for nine controlled reps. Keep two reps in reserve. Record how the set felt."),
                    sentenceIndex: 1, voiceIdentifier: TTSManager.onlineVoiceIdentifier, rate: 1)
                try? EditorDraftStore().save(bookmark, userID: "mock_user", scope: "maia-speech-bookmark-v1")
            }
            #endif
            ttsManager.restorePlayback()
        }
        .onReceive(appState.$isUserLoggedIn.dropFirst()) { _ in
            viewModel.setupView()
            ttsManager.restorePlayback()
        }
        .onChange(of: viewModel.userMessage) { _, _ in viewModel.saveMessages() }
        .onDisappear {
            isComposing = false
            ttsManager.pauseSpeaking()
            viewModel.saveMessages()
        }
        .onReceive(appState.$pendingChatPrompt) { prompt in
            if let prompt = prompt {
                viewModel.userMessage = prompt
                viewModel.sendMessage()
                appState.pendingChatPrompt = nil
            }
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(title: Text("Maia"), message: Text(viewModel.alertMessage), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $viewModel.showingConversations) { MaiaConversationBrowser(model: viewModel) }
        .sheet(isPresented: $viewModel.showingContextControls) { MaiaContextControls(model: viewModel) }
        .sheet(isPresented: $viewModel.showingMealPlanBuilder) {
            MealPlanSurveyView(startingDate: Date())
        }
        .sheet(isPresented: $showingFoodPreferences) {
            SuggestionPreferencesView(goalSettings: goalSettings)
        }
        .sheet(isPresented: $showingSuggestionDetail) {
            if let review = mealSuggestionReview {
                SavedMealSuggestionDetailView(
                    review: review, pantryItemNames: pantryService.pantryItems.map(\.name),
                    remainingCalories: viewModel.remainingCalories, remainingProtein: viewModel.remainingProtein,
                    remainingCarbs: viewModel.remainingCarbs, remainingFats: viewModel.remainingFats,
                    onRegenerate: regenerateMealSuggestion, isRegenerating: isRegeneratingSuggestion,
                    onAccepted: { mealSuggestionReview = nil; mealSuggestion = nil },
                    onDiscarded: { mealSuggestionReview = nil; mealSuggestion = nil }
                )
            }
        }
        .confirmationDialog("Clear Maia chat?", isPresented: $viewModel.showingClearChatConfirmation, titleVisibility: .visible) {
            Button("Clear Chat, Keep Pending Actions", role: .destructive) { viewModel.clearChat() }
            if !viewModel.conversationClearReview.unsubmittedActions.isEmpty {
                Button("Clear Chat & Discard Unsubmitted Actions", role: .destructive) { viewModel.clearChat(discardUnsubmitted: true) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes this device's conversation. \(viewModel.conversationClearReview.unsubmittedActions.count) actions have never been submitted and can be discarded. \(viewModel.conversationClearReview.submittedActions.count) submitted or unconfirmed actions stay available for safe retry; clearing chat cannot cancel them. Saved logs remain. Saved action receipts keep only their outcome and replay identity. \(viewModel.conversationClearReview.unreadableActionCount) unreadable action records will be kept unchanged.")
        }
        }
    }

    private func hideKeyboard() {
        isInputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func sendActionPrompt(_ prompt: String, contract: MaiaContextContract) {
        DIContainer.shared.analyticsManager?.logEvent("maia_action_card_tapped", parameters: [
            "action": contract.action,
            "context_scopes": contract.telemetryScopeList,
            "remaining_calories": Int(viewModel.remainingCalories.rounded()),
            "remaining_protein": Int(viewModel.remainingProtein.rounded()),
            "has_workout": viewModel.workoutCount > 0,
            "has_nutrition_mismatch": hasNutritionMismatch
        ])
        viewModel.userMessage = prompt
        viewModel.sendMessage(contextContract: contract)
    }

    private func generateMealSuggestionFromActionBoard() {
        guard !insightsService.isGeneratingSuggestion,
              let owner = DIContainer.shared.authService.currentUserID,
              let day = dailyLogService.activelyViewedDayContext ?? DiaryDayContext(userID: owner, date: dailyLogService.activelyViewedDate),
              day.isOwned(by: owner) else { return }
        if let saved = MealReviewSaveSession.resumeMealSuggestion(source: "maia_action_card", userID: owner) {
            mealSuggestionReview = saved
            showingSuggestionDetail = true
            return
        }
        HapticManager.instance.feedback(.light)
        Task {
            let pantryNames = pantryService.pantryItems.map(\.name)
            if let suggestion = await insightsService.generateSingleMealSuggestion(pantryItems: pantryNames, day: day) {
                guard DIContainer.shared.authService.currentUserID == owner else { return }
                mealSuggestionReview = suggestion.makeReview(userID: owner, day: day, source: "maia_action_card")
                showingSuggestionDetail = true
            } else {
                guard DIContainer.shared.authService.currentUserID == owner else { return }
                viewModel.alertMessage = "Maia couldn't build a meal right now. Check your connection and try again."
                viewModel.showAlert = true
            }
        }
    }

    private func regenerateMealSuggestion() {
        guard !insightsService.isGeneratingSuggestion, let review = mealSuggestionReview, !review.isLocked,
              let owner = review.userID, owner == DIContainer.shared.authService.currentUserID,
              let current = review.checkpoint.mealSuggestion else { return }
        HapticManager.instance.feedback(.light)
        isRegeneratingSuggestion = true
        Task {
            let next = await insightsService.generateSingleMealSuggestion(
                pantryItems: pantryService.pantryItems.map(\.name), avoiding: [current.mealName], alternative: review.checkpoint.requestedAlternative, day: review.checkpoint.draft.dayContext)
            isRegeneratingSuggestion = false
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            if let next {
                _ = review.replaceMealSuggestion(next)
            } else {
                viewModel.alertMessage = "Maia couldn't build another meal right now. Your current suggestion is kept."
                viewModel.showAlert = true
            }
        }
    }

    private func handleHydrationAction() {
        let contract = MaiaContextContract.hydration
        DIContainer.shared.analyticsManager?.logEvent("maia_action_card_tapped", parameters: [
            "action": contract.action,
            "context_scopes": contract.telemetryScopeList,
            "water_remaining": Int(max(0, viewModel.waterGoal - viewModel.waterOunces).rounded())
        ])
        viewModel.handleMaiaAction(.logWater(amountOunces: 16))
    }

}

private struct MaiaInlineFailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Label("Maia paused", systemImage: "wifi.exclamationmark")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.caution)

            Text(message)
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Retry Question", action: onRetry)
                .buttonStyle(AppActionButtonStyle(.secondary))
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("maia_inline_error")
    }
}
