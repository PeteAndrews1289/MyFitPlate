import SwiftUI

struct AIChatbotView: View {
    @Binding var selectedTab: Int
    var chatContext: String?

    @StateObject private var viewModel = AIChatbotViewModel()

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var pantryService: PantryService

    @Environment(\.colorScheme) var colorScheme
    @StateObject private var ttsManager = TTSManager.shared
    @State private var mealSuggestion: MealSuggestion?
    @State private var showingSuggestionDetail = false
    @State private var isRegeneratingSuggestion = false
    @FocusState private var isInputFocused: Bool

    private var bottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    private var hasNutritionMismatch: Bool {
        dailyLogService.currentDailyLog?.calorieConsistencyStatus().hasMeaningfulMismatch == true
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
        SpotlightTourStep(id: "maia-actions", title: "Quick actions",
                          text: "Tap a card and Maia builds it — fill your remaining macros, get a protein idea, or read your day."),
        SpotlightTourStep(id: "maia-composer", title: "Ask Maia anything",
                          text: "Type a question about food, workouts, or your goals. She already knows today's numbers.")
    ]

    var body: some View {
        SpotlightTourScaffold(steps: AIChatbotView.maiaTourSteps) { isActive in
        VStack(spacing: 0) {
            if viewModel.chatMessages.count <= 1 {
                MaiaBriefingCard(
                    calories: viewModel.remainingCalories,
                    protein: viewModel.remainingProtein,
                    carbs: viewModel.remainingCarbs,
                    fats: viewModel.remainingFats,
                    water: viewModel.waterOunces,
                    waterGoal: viewModel.waterGoal,
                    mealCount: viewModel.mealCount,
                    workoutCount: viewModel.workoutCount
                )
                .padding(.horizontal)
                .padding(.top, 10)

                if canIncludeHealthContext {
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
                chatMessages: $viewModel.chatMessages,
                onLogRecipe: { viewModel.logRecipe(recipeText: $0) },
                onSpeak: ttsManager.speak,
                onAction: { viewModel.handleMaiaAction($0) },
                showAlert: $viewModel.showAlert,
                alertMessage: $viewModel.alertMessage
            )
            .onTapGesture { hideKeyboard() }

            VStack(spacing: 0) {
                // Show the quick-action board whenever the composer is idle (empty + not loading),
                // not just on the very first message. Chat history persists, so gating on message
                // count meant a returning user — anyone who'd ever sent one message — never saw the
                // action board again. Clearing the field brings it back.
                if viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isLoading && !isInputFocused {
                    MaiaActionBoardView(
                        remainingCalories: viewModel.remainingCalories,
                        remainingProtein: viewModel.remainingProtein,
                        waterRemaining: max(0, viewModel.waterGoal - viewModel.waterOunces),
                        hasWorkoutToday: viewModel.workoutCount > 0,
                        hasNutritionMismatch: hasNutritionMismatch,
                        healthKitEnabled: canIncludeHealthContext,
                        pantryCount: pantryService.pantryItems.count,
                        isGeneratingMeal: insightsService.isGeneratingSuggestion,
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
                    .padding(.vertical, 6)
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
                        
                        MaiaTypingIndicator()
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                HStack(spacing: 10) {
                    TextField("Ask Maia anything", text: $viewModel.userMessage, axis: .vertical)
                        .focused($isInputFocused)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.backgroundPrimary.opacity(colorScheme == .dark ? 0.62 : 0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .lineLimit(1...4)
                        .onSubmit { viewModel.sendMessage() }

                    Button(action: { viewModel.sendMessage() }) {
                        Image(systemName: "arrow.up")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(
                                viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading
                                ? Color(UIColor.tertiaryLabel)
                                : Color.brandPrimary,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, bottomSafeAreaInset)
                .featureSpotlight(isActive: isActive("maia-composer"))
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
            if viewModel.chatMessages.count > 1 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showingClearChatConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear Maia chat")
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isInputFocused = false
                    hideKeyboard()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.brandPrimary)
                }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
        .onAppear {
            viewModel.chatContext = self.chatContext
            viewModel.dailyLogService = self.dailyLogService
            viewModel.goalSettings = self.goalSettings
            viewModel.achievementService = self.achievementService
            viewModel.mealPlannerService = self.mealPlannerService
            viewModel.healthKitViewModel = self.healthKitViewModel
            viewModel.setupView()
        }
        .onDisappear {
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
            Alert(title: Text("Notification"), message: Text(viewModel.alertMessage), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showingSuggestionDetail) {
            if let mealSuggestion {
                MealSuggestionDetailView(
                    suggestion: mealSuggestion,
                    pantryItemNames: pantryService.pantryItems.map(\.name),
                    remainingCalories: viewModel.remainingCalories,
                    remainingProtein: viewModel.remainingProtein,
                    remainingCarbs: viewModel.remainingCarbs,
                    remainingFats: viewModel.remainingFats,
                    onLog: logMealSuggestion,
                    onRegenerate: regenerateMealSuggestion,
                    isRegenerating: isRegeneratingSuggestion
                )
            }
        }
        .confirmationDialog("Clear Maia chat?", isPresented: $viewModel.showingClearChatConfirmation, titleVisibility: .visible) {
            Button("Clear Chat", role: .destructive) { viewModel.clearChat() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the saved conversation history on this device.")
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
        guard !insightsService.isGeneratingSuggestion else { return }
        HapticManager.instance.feedback(.light)
        Task {
            let pantryNames = pantryService.pantryItems.map(\.name)
            let contract = MaiaContextContract.fillMacros
            DIContainer.shared.analyticsManager?.logEvent("maia_action_card_tapped", parameters: [
                "action": contract.action,
                "context_scopes": contract.telemetryScopeList,
                "remaining_calories": Int(viewModel.remainingCalories.rounded()),
                "remaining_protein": Int(viewModel.remainingProtein.rounded()),
                "pantry_count": pantryNames.count
            ])

            if let suggestion = await insightsService.generateSingleMealSuggestion(pantryItems: pantryNames) {
                mealSuggestion = suggestion
                showingSuggestionDetail = true
                DIContainer.shared.analyticsManager?.logEvent("maia_action_card_generated", parameters: [
                    "action": contract.action,
                    "context_scopes": contract.telemetryScopeList,
                    "calories": Int(suggestion.calories.rounded()),
                    "protein": Int(suggestion.protein.rounded())
                ])
            } else {
                viewModel.alertMessage = "Maia couldn't build a meal right now. Check your connection and try again."
                viewModel.showAlert = true
            }
        }
    }

    private func regenerateMealSuggestion() {
        guard !insightsService.isGeneratingSuggestion, let current = mealSuggestion else { return }
        HapticManager.instance.feedback(.light)
        isRegeneratingSuggestion = true
        Task {
            let pantryNames = pantryService.pantryItems.map(\.name)
            let next = await insightsService.generateSingleMealSuggestion(pantryItems: pantryNames, avoiding: [current.mealName])
            isRegeneratingSuggestion = false
            if let next {
                mealSuggestion = next
            } else {
                viewModel.alertMessage = "Maia couldn't build another meal right now. Try again in a moment."
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

    private func logMealSuggestion(_ suggestion: MealSuggestion) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }

        let foodItem = FoodItem(
            id: UUID().uuidString,
            name: suggestion.mealName,
            calories: suggestion.calories,
            protein: suggestion.protein,
            carbs: suggestion.carbs,
            fats: suggestion.fats,
            servingSize: "1 serving (Maia Estimate)",
            servingWeight: 0,
            timestamp: Date()
        )
        .withAIEstimateSource(.aiChat, sourceName: "Maia Action")

        dailyLogService.addFoodToCurrentLog(for: userID, foodItem: foodItem, source: "maia_action_card")
        DIContainer.shared.analyticsManager?.logEvent("maia_action_card_logged", parameters: [
            "action": MaiaContextContract.fillMacros.action,
            "context_scopes": MaiaContextContract.fillMacros.telemetryScopeList,
            "calories": Int(suggestion.calories.rounded()),
            "protein": Int(suggestion.protein.rounded())
        ])
        mealSuggestion = nil
    }
}
