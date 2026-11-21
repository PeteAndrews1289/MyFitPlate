import SwiftUI
import MyFitPlateCore

@MainActor
class AIChatbotViewModel: ObservableObject {
    @Published var userMessage = ""
    @Published var chatMessages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var showingClearChatConfirmation = false
    @Published var showingMealPlanBuilder = false
    @Published var requestStage = "Waiting for Maia"
    @Published private(set) var partialResponse = ""
    @Published private(set) var conversationLibrary = MaiaConversationLibrary()
    @Published private(set) var storageError: String?
    @Published private(set) var hasConversationConflict = false
    @Published var showingConversations = false
    @Published var showingContextControls = false
    @Published private(set) var isSavingCommunication = false
    @Published var inlineErrorMessage: String?
    @Published private(set) var isSavingAction = false
    @Published private(set) var conversationClearReview = MaiaConversationClearReview()
    @Published private(set) var retainedMaiaActions: [MaiaSavedActionReceipt] = []

    private var currentActionSession: MaiaActionSaveSession?
    private var activeActionRequestID: UUID?
    private let actionStore: EditorDraftStore
    private let chatDefaults: UserDefaults
    private let conversationStore: MaiaConversationStore
    private var requestTask: Task<Void, Never>?
    private var communicationRequestID: UUID?
    private var pendingResponse: (ownerID: String, conversationID: UUID, requestID: UUID, response: MaiaAIResponse)?
    var canStartNewRequest: Bool { !isLoading && pendingResponse == nil }

    init(actionStore: EditorDraftStore = EditorDraftStore(), chatDefaults: UserDefaults = .standard) {
        self.actionStore = actionStore; self.chatDefaults = chatDefaults
        conversationStore = MaiaConversationStore(drafts: actionStore)
    }

    private var retryMessage: String?
    private var retryContextContract: MaiaContextContract?
    private var activeRequestID: UUID?
    private var activeAccountID: String?
    
    var chatContext: String?
    
    // Service references
    var dailyLogService: DailyLogService?
    var goalSettings: GoalSettings?
    var achievementService: AchievementService?
    var mealPlannerService: MealPlannerService?
    var healthKitViewModel: HealthKitViewModel?
    
    func setupView() {
        let userID = DIContainer.shared.authService.currentUserID
        if activeAccountID != userID {
            requestTask?.cancel()
            requestTask = nil
            pendingResponse = nil
            partialResponse = ""
            conversationLibrary = .init()
            userMessage = ""; storageError = nil; hasConversationConflict = false
            showingConversations = false; showingContextControls = false
            communicationRequestID = nil; isSavingCommunication = false
            activeRequestID = nil
            activeAccountID = userID
            isLoading = false
            inlineErrorMessage = nil
            retryMessage = nil
            retryContextContract = nil
            isSavingAction = false
            currentActionSession = nil
            activeActionRequestID = nil
            showingMealPlanBuilder = false
            chatMessages.removeAll()
            loadMessages()
        } else if chatMessages.isEmpty {
            loadMessages()
        }
        if let userID {
            dailyLogService?.fetchLog(for: userID, date: dailyLogService?.activelyViewedDate ?? Date()) { _ in }
        }
        refreshRetainedMaiaActions()
        if chatMessages.isEmpty {
            let initialMessage = ChatMessage(id: UUID(), text: welcomeMessage(), isUser: false)
            chatMessages.append(initialMessage)
            saveMessages()
        }
    }
    
    func reviewClearChat() {
        guard let userID = activeAccountID, DIContainer.shared.authService.currentUserID == userID else { return }
        do {
            conversationClearReview = try MaiaActionSaveSession.reviewConversationClear(userID: userID, messages: chatMessages, store: actionStore)
            showingClearChatConfirmation = true
        } catch {
            alertMessage = "The saved action review could not be opened. Your conversation and actions are kept; retry safely."
            showAlert = true
        }
    }

    func clearChat(discardUnsubmitted: Bool = false) {
        guard let userID = activeAccountID, DIContainer.shared.authService.currentUserID == userID else { return }
        do {
            try MaiaActionSaveSession.clearConversation(userID: userID, messages: chatMessages,
                                                       discardUnsubmitted: discardUnsubmitted, store: actionStore)
        } catch {
            alertMessage = "Chat could not be cleared completely. Saved logs remain. Your conversation is kept; retry safely."
            showAlert = true
            return
        }
        requestTask?.cancel()
        requestTask = nil
        pendingResponse = nil
        partialResponse = ""
        updateCurrentConversation { $0.request = nil; $0.draft = ""; $0.title = "New conversation"; $0.context.notes = "" }
        TTSManager.shared.clearCachedSpeech(for: userID)
        userMessage = ""
        activeRequestID = nil
        isLoading = false
        inlineErrorMessage = nil
        retryMessage = nil
        retryContextContract = nil
        chatMessages.removeAll()
        chatMessages.append(ChatMessage(id: UUID(), text: welcomeMessage(), isUser: false))
        saveMessages()
        refreshRetainedMaiaActions()
    }

    private func refreshRetainedMaiaActions() {
        guard let userID = activeAccountID, DIContainer.shared.authService.currentUserID == userID,
              let review = try? MaiaActionSaveSession.reviewConversationClear(userID: userID, store: actionStore) else {
            retainedMaiaActions = []
            return
        }
        retainedMaiaActions = (review.submittedActions + review.unsubmittedActions).filter(\.conversationCleared)
    }

    func retryRetainedMaiaAction(_ receipt: MaiaSavedActionReceipt) {
        guard let command = receipt.command else { return }
        performSavedCommand(command, actionID: receipt.actionID) { [weak self] _ in self?.refreshRetainedMaiaActions() }
    }
    
    // MARK: - Computed Properties for Context
    
    private var relevantDailyLog: DailyLog? {
        guard let service = dailyLogService else { return nil }
        let logDate = service.activelyViewedDate
        return service.currentDailyLog.flatMap { log in
            Calendar.current.isDate(log.date, inSameDayAs: logDate) ? log : nil
        }
    }
    
    var remainingCalories: Double {
        let total = relevantDailyLog?.totalCalories() ?? 0
        let goal = goalSettings?.calories ?? 2000
        return max(0, goal - total)
    }

    var remainingProtein: Double {
        let total = relevantDailyLog?.totalMacros().protein ?? 0
        return max(0, (goalSettings?.protein ?? 0) - total)
    }

    var remainingFats: Double {
        let total = relevantDailyLog?.totalMacros().fats ?? 0
        return max(0, (goalSettings?.fats ?? 0) - total)
    }

    var remainingCarbs: Double {
        let total = relevantDailyLog?.totalMacros().carbs ?? 0
        return max(0, (goalSettings?.carbs ?? 0) - total)
    }

    var mealCount: Int {
        relevantDailyLog?.meals.filter { !$0.foodItems.isEmpty }.count ?? 0
    }

    var workoutCount: Int {
        relevantDailyLog?.exercises?.count ?? 0
    }

    var waterOunces: Double {
        relevantDailyLog?.waterTracker?.totalOunces ?? 0
    }

    var waterGoal: Double {
        if let goalSettings {
            return goalSettings.hydrationTarget(for: relevantDailyLog?.date ?? Date(), recordedGoal: relevantDailyLog?.waterTracker?.goalOunces) ?? 0
        }
        return relevantDailyLog?.waterTracker?.goalOunces ?? 0
    }

    private var canShareHealthDataWithAI: Bool {
        guard let userID = DIContainer.shared.authService.currentUserID,
              healthKitViewModel?.hasSyncedHealthData == true else { return false }
        return AIDataConsentStore.shared.allowsHealthData(for: userID)
    }

    private func welcomeMessage() -> String {
        guard relevantDailyLog != nil else {
            return "I can turn your remaining nutrition and training into a practical next step. What would help most today?"
        }

        let calories = Int(remainingCalories.rounded()).formatted()
        let protein = Int(remainingProtein.rounded()).formatted()

        if remainingProtein >= 10 {
            return "You have \(calories) calories and \(protein)g protein left today. Want me to turn that into a practical meal?"
        }

        return "You have \(calories) calories left today. Ask me for a meal idea or a quick read on what you've logged."
    }

    private var todayFoodItems: [FoodItem] {
        relevantDailyLog?.meals.flatMap(\.foodItems) ?? []
    }

    private var aiEstimateCount: Int {
        todayFoodItems.filter { item in
            switch item.sourceMetadata?.sourceType {
            case .aiImage?, .aiMenu?, .aiText?, .aiChat?:
                return true
            default:
                return false
            }
        }.count
    }

    private func promptContextSummary(for contract: MaiaContextContract) -> String {
        let log = relevantDailyLog
        let macros = log?.totalMacros() ?? (protein: 0, fats: 0, carbs: 0)
        let caloriesLogged = log?.totalCalories() ?? 0
        let consistencyStatus = log?.calorieConsistencyStatus()
        let flaggedFoods = log?.foodsWithMeaningfulCalorieMacroMismatch().map(\.name).prefix(4).joined(separator: ", ") ?? "None"
        let exerciseNames = log?.exercises?.map(\.name).joined(separator: ", ") ?? "None"

        let hkSteps = healthKitViewModel?.todaySteps ?? 0
        let hkActiveEnergy = healthKitViewModel?.todayActiveEnergy ?? 0
        let sleepHours = healthKitViewModel?.sleepSummary.lastNightHours ?? 0
        let sleepScore = healthKitViewModel?.sleepSummary.lastNightScore ?? healthKitViewModel?.sleepSummary.averageScore
        let macroCalories = consistencyStatus?.macroDerivedCalories ?? 0
        let calorieDelta = consistencyStatus?.delta ?? 0
        let auditStatus = consistencyStatus?.hasMeaningfulMismatch == true
            ? "Needs review: macros imply \(Int(abs(calorieDelta).rounded())) calories \(calorieDelta > 0 ? "more" : "less") than logged."
            : "No meaningful mismatch."

        var sections: [String] = []

        if contract.allows(.nutritionGoals) {
            sections.append("""
            Remaining nutrition goals:
            - Calories: \(String(format: "%.0f", remainingCalories)) cal
            - Protein: \(String(format: "%.0f", remainingProtein)) g
            - Fats: \(String(format: "%.0f", remainingFats)) g
            - Carbs: \(String(format: "%.0f", remainingCarbs)) g
            """)
        }

        if contract.allows(.todayLog) {
            sections.append("""
            Today's logged food totals:
            - Whole-day review: \(log.map { NutritionDayEvidence.status(of: $0).title } ?? "Not reviewed"). These are entries so far; do not infer full-day intake or adherence unless fully logged.
            - Calories logged: \(Int(caloriesLogged.rounded())) of \(Int((goalSettings?.calories ?? 0).rounded())) target
            - Protein logged: \(Int(macros.protein.rounded()))g of \(Int((goalSettings?.protein ?? 0).rounded()))g target
            - Carbs logged: \(Int(macros.carbs.rounded()))g of \(Int((goalSettings?.carbs ?? 0).rounded()))g target
            - Fats logged: \(Int(macros.fats.rounded()))g of \(Int((goalSettings?.fats ?? 0).rounded()))g target
            - Meals logged: \(mealCount)
            """)
        }

        if contract.allows(.nutritionAudit) {
            sections.append("""
            Nutrition audit:
            - Macro-derived calories: \(Int(macroCalories.rounded()))
            - Status: \(auditStatus)
            - Flagged foods: \(flaggedFoods)
            """)
        }

        if contract.allows(.water) {
            sections.append("""
            Water progress:
            - Water logged: \(Int(waterOunces.rounded())) oz. \(waterGoal > 0 ? "Daily target: \(Int(waterGoal.rounded())) oz." : "Tracking only: no daily target or remaining amount. Do not suggest catching up to a target.")
            """)
        }

        if contract.allows(.loggedTraining) {
            sections.append("""
            Logged training:
            - Workouts logged: \(workoutCount) (\(exerciseNames))
            """)
        }

        if contract.allows(.coachingPreferences) {
            sections.append("""
            User coaching preferences:
            - Training intent: \(goalSettings?.trainingIntent ?? "")
            - Reminder style: \(goalSettings?.reminderStyle ?? "")
            - Maia style: \(goalSettings?.maiaTone ?? "")
            """)
        }

        if contract.allows(.healthKit), canShareHealthDataWithAI {
            sections.append("""
            Passive Health Data (For Coaching Context Only):
            - Steps Today: \(Int(hkSteps))
            - Passive Active Energy Burned: \(Int(hkActiveEnergy)) kcal
            - Sleep Last Night: \(String(format: "%.1f", sleepHours)) hours
            - Sleep Score: \(sleepScore.map { "\($0)" } ?? "Unavailable")
            """)
        }

        if contract.allows(.aiEstimates) {
            sections.append("""
            AI estimate boundary:
            - AI-estimated foods in today's log: \(aiEstimateCount)
            - Treat estimates as reviewable, not exact label data.
            """)
        }

        return sections.joined(separator: "\n\n")
    }
    
    // MARK: - Actions
    
    func sendMessage(contextContract: MaiaContextContract? = nil) {
        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, canStartNewRequest else { return }
        let mayShareHealthData = canShareHealthDataWithAI
        let effectiveContract = currentConversationContext.restricting(contextContract ?? .generalChat(includeHealthKit: mayShareHealthData))
            .respectingHealthDataConsent(mayShareHealthData)

        let userMsg = ChatMessage(id: UUID(), text: trimmedMessage, isUser: true)
        chatMessages.append(userMsg)
        DIContainer.shared.analyticsManager.log(.aiFeatureUsed, ["feature": AIFeature.maiaChat.rawValue])
        DIContainer.shared.analyticsManager?.logEvent("maia_context_contract_used", parameters: [
            "action": effectiveContract.action,
            "scopes": effectiveContract.telemetryScopeList,
            "uses_healthkit": effectiveContract.allows(.healthKit)
        ])
        HapticManager.instance.feedback(.light)

        userMessage = ""
        submitRequest(message: trimmedMessage, questionMessageID: userMsg.id, contextContract: effectiveContract)
    }

    func retryLastMessage() {
        guard let request = currentConversation?.request, !request.isPending, !isLoading,
              request.state != .completed else { return }
        let contract = currentConversationContext.restricting(request.contract).respectingHealthDataConsent(canShareHealthDataWithAI)
        submitRequest(message: request.question, questionMessageID: request.questionMessageID, contextContract: contract, retry: request)
    }

    func cancelRequest() {
        requestTask?.cancel(); requestTask = nil
        activeRequestID = nil; isLoading = false; partialResponse = ""
        inlineErrorMessage = "Request cancelled. Your question is kept; nothing was logged or changed."
        updateCurrentConversation { conversation in
            guard conversation.request?.isPending == true else { return }
            conversation.request?.state = .cancelled
            conversation.request?.partialText = ""
            conversation.request?.errorMessage = self.inlineErrorMessage
        }
        saveMessages()
    }

    private func submitRequest(message: String, questionMessageID: UUID, contextContract: MaiaContextContract,
                               retry: MaiaConversationRequest? = nil) {
        guard let requestAccountID = DIContainer.shared.authService.currentUserID,
              requestAccountID == activeAccountID, let conversationID = currentConversation?.id else {
            inlineErrorMessage = "Sign in again before asking Maia."
            return
        }
        let attemptID = UUID()
        var request = retry ?? MaiaConversationRequest(questionMessageID: questionMessageID, question: message,
            contextDate: dailyLogService?.activelyViewedDate ?? Date(), contract: contextContract)
        if retry != nil { request.attempts += 1 }
        request.state = .waiting; request.partialText = ""; request.errorMessage = nil
        request.contract = contextContract; request.contextDate = dailyLogService?.activelyViewedDate ?? Date()
        updateCurrentConversation { $0.request = request }
        guard saveMessages() else {
            inlineErrorMessage = "Your question is kept, but it could not be saved or sent. Retry saving before asking again."
            updateCurrentConversation { $0.request?.state = .failed; $0.request?.errorMessage = self.inlineErrorMessage }
            return
        }
        activeRequestID = attemptID
        isLoading = true; partialResponse = ""; inlineErrorMessage = nil
        retryMessage = message; retryContextContract = contextContract
        requestStage = "Waiting for Maia"
        let requestID = request.id
        let messages = requestMessages(for: message, contextContract: contextContract)
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result: Result<MaiaAIResponse, AIError>
            if let streaming = DIContainer.shared.aiService as? AIStreamingServiceProtocol {
                result = await streaming.performStreamingRequest(messages: messages, model: "gpt-6-astra", maxTokens: 1000,
                    temperature: 0.5, requestKind: .coaching, requestID: requestID) { [weak self] delta in
                        guard let self, self.activeRequestID == attemptID, self.currentConversation?.id == conversationID,
                              DIContainer.shared.authService.currentUserID == requestAccountID else { return }
                        self.partialResponse += delta
                        self.requestStage = "Maia is answering"
                        self.updateCurrentConversation { $0.request?.state = .streaming; $0.request?.partialText = self.partialResponse }
                    }
            } else {
                result = await DIContainer.shared.aiService.performRequest(messages: messages, model: "gpt-6-astra",
                    maxTokens: 1000, temperature: 0.5, requestKind: .coaching).map { MaiaAIResponse(content: $0) }
            }
            guard !Task.isCancelled, self.activeRequestID == attemptID,
                  self.currentConversation?.id == conversationID, self.activeAccountID == requestAccountID,
                  DIContainer.shared.authService.currentUserID == requestAccountID else { return }
            self.activeRequestID = nil; self.requestTask = nil; self.isLoading = false; self.partialResponse = ""
            if let saved = try? self.conversationStore.load(userID: requestAccountID), saved.revisionID != self.conversationLibrary.revisionID {
                self.hasConversationConflict = true
                self.storageError = MaiaConversationStoreError.changed.localizedDescription
                return
            }
            switch result {
            case .success(let response):
                self.pendingResponse = (requestAccountID, conversationID, requestID, response)
                _ = self.persistPendingResponse()
                return
            case .failure(let error):
                self.inlineErrorMessage = self.userFacingRequestError(error)
                self.updateCurrentConversation {
                    $0.request?.state = .failed; $0.request?.partialText = ""; $0.request?.errorMessage = self.inlineErrorMessage
                }
                HapticManager.instance.notification(.warning)
            }
            self.saveMessages()
        }
    }

    private func userFacingRequestError(_ error: Error) -> String {
        if let error = error as? AIError {
            switch error {
            case .consentRequired, .consentChanged, .accountChanged, .featureUnavailable: return error.localizedDescription
            case .apiError(let message): return message
            default: break
            }
        }
        let description = error.localizedDescription.lowercased()
        if description.contains("offline") ||
            description.contains("internet") ||
            description.contains("network") ||
            description.contains("connection") {
            return "You appear to be offline. Your question is still here and can be retried when the connection returns."
        }
        return "Maia could not reach the response service. Your question is still here and nothing was logged or changed."
    }
    
    private func requestMessages(for message: String, contextContract: MaiaContextContract) -> [[String: Any]] {
        let systemPrompt = """
        You are Maia, the personal nutrition and training coach inside MyFitPlate.
        Your style is warm, concise, practical, and specific to the user's logged day. Avoid generic wellness filler.
        Do not diagnose medical conditions or present estimates as clinical truth.
        Respect the user's coaching preferences in the context. If reminder style is Minimal, be brief. If Direct, be crisp and action-oriented. If Gentle, be encouraging without being vague.
        \(effectiveCommunicationProfile.promptInstructions)
        If the nutrition audit says calories and macros meaningfully disagree, mention that logged calories remain official but the item should be reviewed before making precise calorie-budget claims.
        Respect the user's calorie target. Training fuel should be planned before hard sessions and kept inside the user's chosen target unless the user explicitly changes the target. If the user is already over target, do not give it a special mode label, do not celebrate it, and do not frame accidental over-target intake as performance fuel; give a neutral review and the next best on-target choice.
        \(contextContract.promptSummary)

        You can propose reviewed actions. Never claim an action was saved or performed before the user explicitly confirms the app's review. When the user asks you to log a workout, generate a meal plan, log a meal, log water, start/stop a fast, or log their weight, you MUST provide a structured JSON block AT THE END of your message.
        
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
        The user enters weight in \(BodyUnits.weightUnit(metric: BodyUnits.prefersMetric())). ALWAYS return "weightPounds" in POUNDS — if the stated weight is in kilograms, convert it (1 kg = 2.20462 lb).
        ```json
        {
          "type": "log_weight",
          "weightPounds": 150.5
        }
        ```

        You may include conversational text BEFORE the JSON block. Do not include any text after the JSON block.
        If data is missing, say what assumption you are making.
        For your own AI estimates, keep calories reasonably consistent with protein*4 + carbs*4 + fats*9. Do not invent exact precision for restaurant or packaged foods.

        Context date: \((dailyLogService?.activelyViewedDate ?? Date()).formatted(date: .complete, time: .omitted)). Only describe this as today if it is actually today's date.
        \(promptContextSummary(for: contextContract))
        \(currentConversationContext.includeRecentMessages ? (chatContext.map { "Additional context: \($0)" } ?? "") : "")
        """

        var messagesForAPI: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        let topicSummary = currentConversationContext.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !topicSummary.isEmpty {
            // This is user-authored context, never a privileged summary of other source text.
            messagesForAPI.append(["role": "user", "content": "My saved topic summary (written by me, not verified measurements): " + topicSummary])
        }

        let history = currentConversationContext.includeRecentMessages ? Array(chatMessages.dropLast().suffix(6)) : []
        for chatMessage in history where !chatMessage.text.isEmpty {
            messagesForAPI.append(["role": chatMessage.isUser ? "user" : "assistant", "content": chatMessage.text])
        }

        messagesForAPI.append(["role": "user", "content": message])

        return messagesForAPI
    }

    // MARK: - Action Handling

    func logRecipe(recipeText: String, actionID: String? = nil, completion: @escaping (Bool) -> Void = { _ in }) {
        let nutrients = parseNutritionalBreakdown(from: recipeText)
        guard let calories = nutrients["calories"], let protein = nutrients["protein"],
              let fats = nutrients["fats"], let carbs = nutrients["carbs"],
              [calories, protein, fats, carbs].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            alertMessage = "This response needs complete nutrition details before it can be logged."
            showAlert = true
            completion(false)
            return
        }
        let food = FoodItem(
            id: "maia-food", name: extractFoodName(from: recipeText), calories: calories,
            protein: protein, carbs: carbs, fats: fats, servingSize: "1 serving (AI Est.)",
            servingWeight: 0, calcium: nutrients["calcium"], iron: nutrients["iron"],
            potassium: nutrients["potassium"], sodium: nutrients["sodium"], vitaminA: nutrients["vitaminA"],
            vitaminC: nutrients["vitaminC"], vitaminD: nutrients["vitaminD"]
        ).withAIEstimateSource(.aiChat, sourceName: "Maia Chat")
        performSavedCommand(.meal(food), actionID: actionID, completion: completion)
    }

    func handleMaiaAction(_ action: MaiaAction, actionID: String? = nil, completion: @escaping (Bool) -> Void = { _ in }) {
        if case .generateMealPlan = action {
            guard !isSavingAction, DIContainer.shared.authService.currentUserID != nil,
                  mealPlannerService != nil, goalSettings != nil else { completion(false); return }
            // Opening a builder is navigation; only its reviewed Save can claim a result.
            showingMealPlanBuilder = true
            completion(false)
            return
        }
        let command: MaiaSavedCommand
        switch action {
        case .logWorkout(let name, let minutes, let calories): command = .workout(name: name, minutes: minutes, calories: calories)
        case .logWater(let ounces): command = .water(ounces: ounces)
        case .logWeight(let pounds): command = .weight(pounds: pounds)
        case .startFast(let hours): command = .startFast(hours: hours)
        case .stopFast: command = .stopFast
        case .generateMealPlan: return
        }
        performSavedCommand(command, actionID: actionID, completion: completion)
    }

    private func performSavedCommand(_ command: MaiaSavedCommand, actionID: String?, completion: @escaping (Bool) -> Void) {
        guard !isSavingAction else { completion(false); return }
        guard let userID = DIContainer.shared.authService.currentUserID, let dailyLogService else {
            alertMessage = "Sign in before saving this action."
            showAlert = true
            completion(false)
            return
        }
        let session = MaiaActionSaveSession(userID: userID, actionID: actionID, store: actionStore)
        var fastSessionID: UUID?
        if case .stopFast = command {
            FastingManager.shared.activateAccount(userID)
            fastSessionID = FastingManager.shared.session?.id
            guard fastSessionID != nil || session.receipt?.fastSessionID != nil || session.receipt?.isAccepted == true else {
                alertMessage = "There is no active saved fast to end."
                showAlert = true
                completion(false)
                return
            }
        }
        guard session.prepare(command: command, date: dailyLogService.activelyViewedDate,
                              mealName: determineMealType(), fastSessionID: fastSessionID) else {
            alertMessage = session.errorMessage ?? "Your pending action is kept. Review it before retrying."
            showAlert = true
            completion(false)
            return
        }
        isSavingAction = true
        currentActionSession = session
        let alreadyAccepted = session.receipt?.isAccepted == true
        let requestID = UUID()
        activeActionRequestID = requestID
        session.save(using: dailyLogService, goals: goalSettings, waterGoal: waterGoal,
            external: { [weak self] receipt, done in
                guard let self else { done(false); return }
                self.performFastingCommand(receipt, userID: userID, completion: done)
            },
            completion: { [weak self] accepted in
                guard let self, self.activeActionRequestID == requestID else { completion(false); return }
                self.activeActionRequestID = nil
                if accepted, !alreadyAccepted {
                    switch command {
                    case .meal: self.achievementService?.checkFeatureUsedAchievement(userID: userID, featureType: .aiRecipeLogged)
                    case .workout: DIContainer.shared.analyticsManager?.logEvent("workout_logged_ai", parameters: nil)
                    default: break
                    }
                }
                let failure = session.errorMessage ?? "Your action is kept. Retry safely."
                let message = accepted ? self.savedActionMessage(session.receipt)
                    : failure.localizedCaseInsensitiveContains("was saved") ? failure : "Couldn't save this action. \(failure)"
                self.finishAction(accepted, userID: userID, message: message, completion: completion)
            })
    }

    private func performFastingCommand(_ receipt: MaiaSavedActionReceipt, userID: String, completion: @escaping (Bool) -> Void) {
        guard DIContainer.shared.authService.currentUserID == userID,
              let ownerScope = FastingSessionStore.ownerScope(userID: userID),
              let command = receipt.command else { completion(false); return }
        let manager = FastingManager.shared
        manager.activateAccount(userID)
        do {
            let history = try FastingSessionStore().load(ownerScope: ownerScope)
            switch command {
            case .startFast(let hours):
                let source = "maia:\(receipt.entryID)"
                if history.sessions.contains(where: { $0.source == source }) {
                    manager.recoverState()
                    completion(true)
                } else {
                    completion(manager.startFast(hours: hours, source: source))
                }
            case .stopFast:
                guard let target = receipt.fastSessionID, let recorded = history.sessions.first(where: { $0.id == target }) else {
                    completion(false)
                    return
                }
                if !recorded.isActive {
                    manager.recoverState()
                    completion(true)
                } else {
                    guard manager.session?.id == target else { completion(false); return }
                    completion(manager.endFast())
                }
            default: completion(false)
            }
        } catch { completion(false) }
    }

    private func savedActionMessage(_ receipt: MaiaSavedActionReceipt?) -> String {
        guard let receipt, let command = receipt.command else { return "Action saved." }
        switch command {
        case .water(let ounces): return "\(ounces.formatted(.number.precision(.fractionLength(0...1)))) oz of water logged."
        case .workout(let name, _, _): return "\(name) logged."
        case .meal(let food): return "\(food.name) added to \(receipt.mealName.lowercased())."
        case .weight(let pounds):
            let metric = BodyUnits.prefersMetric()
            return "Weight updated to \(String(format: "%.1f", BodyUnits.weightDisplayValue(lbs: pounds, metric: metric))) \(BodyUnits.weightUnit(metric: metric))."
        case .startFast: return "Fast started."
        case .stopFast: return "Fast ended."
        }
    }

    private func finishAction(_ accepted: Bool, userID: String, message: String, completion: (Bool) -> Void) {
        isSavingAction = false
        currentActionSession = nil
        guard DIContainer.shared.authService.currentUserID == userID else { completion(false); return }
        refreshRetainedMaiaActions()
        if accepted { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        alertMessage = message
        showAlert = true
        completion(accepted)
    }

    // MARK: - Parsing Helpers
    
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
                for greeting in commonGreetings where lowerFirstLine.starts(with: greeting) {
                    potentialTitle = String(potentialTitle.dropFirst(greeting.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
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

    private func determineMealType() -> String { 
        let h = Calendar.current.component(.hour, from: Date())
        switch h { 
        case 0..<4: return "Snack"
        case 4..<11: return "Breakfast"
        case 11..<16: return "Lunch"
        case 16..<21: return "Dinner"
        default: return "Snack" 
        } 
    }

    // MARK: - Persistence
    
    var currentConversation: MaiaConversation? {
        conversationLibrary.conversations.first { $0.id == conversationLibrary.selectedID }
    }

    var currentConversationContext: MaiaConversationContext { currentConversation?.context ?? .init() }
    var effectiveCommunicationProfile: MaiaCommunicationProfile {
        if let override = currentConversation?.communicationOverride { return override }
        var profile = conversationLibrary.profile
        profile.tone = goalSettings?.maiaTone ?? profile.tone
        return profile
    }
    var contextSummary: String {
        let count = currentConversationContext.includedScopes.count
        let memory = currentConversationContext.includeRecentMessages ? "Recent messages included" : "No message history shared"
        return "\(count) context categories · \(memory)"
    }

    func updateContext(_ context: MaiaConversationContext, profile: MaiaCommunicationProfile, onlyThisTopic: Bool) async -> Bool {
        guard !isSavingCommunication, let owner = activeAccountID, owner == DIContainer.shared.authService.currentUserID,
              let conversationID = currentConversation?.id else { return false }
        let requestID = UUID()
        communicationRequestID = requestID; isSavingCommunication = true
        defer {
            if communicationRequestID == requestID { isSavingCommunication = false; communicationRequestID = nil }
        }
        if !onlyThisTopic, profile.tone != goalSettings?.maiaTone {
            do {
                // A tone-only merge must not replay nutrition targets or any other profile snapshot.
                try await DIContainer.shared.settingsRepository.saveUserGoals(userID: owner, data: ["goals": ["maiaTone": profile.tone]])
                guard owner == activeAccountID, owner == DIContainer.shared.authService.currentUserID,
                      conversationID == currentConversation?.id else { return false }
                goalSettings?.maiaTone = profile.tone
            } catch {
                guard owner == activeAccountID, owner == DIContainer.shared.authService.currentUserID else { return false }
                storageError = "Communication settings could not be saved. Your choices are kept in this review; retry when connected."
                return false
            }
        }
        updateCurrentConversation { $0.context = context; $0.communicationOverride = onlyThisTopic ? profile : nil }
        if !onlyThisTopic { conversationLibrary.profile = profile }
        return saveMessages()
    }

    func newConversation() {
        guard activeAccountID == DIContainer.shared.authService.currentUserID else { return }
        if isLoading { cancelRequest() }
        guard saveMessages() else { return }
        let conversation = MaiaConversation(messages: [ChatMessage(text: welcomeMessage(), isUser: false)])
        conversationLibrary.conversations.insert(conversation, at: 0)
        conversationLibrary.selectedID = conversation.id
        projectSelectedConversation()
        saveMessages()
    }

    func selectConversation(_ id: UUID) {
        guard activeAccountID == DIContainer.shared.authService.currentUserID,
              conversationLibrary.conversations.contains(where: { $0.id == id }) else { return }
        if isLoading { cancelRequest() }
        guard saveMessages() else { return }
        conversationLibrary.selectedID = id
        projectSelectedConversation()
        saveMessages()
    }

    private func updateCurrentConversation(_ edit: (inout MaiaConversation) -> Void) {
        guard let index = conversationLibrary.conversations.firstIndex(where: { $0.id == conversationLibrary.selectedID }) else { return }
        edit(&conversationLibrary.conversations[index])
    }

    private func projectSelectedConversation() {
        guard let conversation = currentConversation else { return }
        chatMessages = conversation.messages; userMessage = conversation.draft
        partialResponse = ""; inlineErrorMessage = conversation.request?.errorMessage
        retryMessage = conversation.request?.question; retryContextContract = conversation.request?.contract
        isLoading = false
    }

    private func loadMessages() {
        guard let userID = activeAccountID, userID == DIContainer.shared.authService.currentUserID else { return }
        do {
            conversationLibrary = try conversationStore.loadOrMigrate(userID: userID, defaults: chatDefaults, legacyTone: goalSettings?.maiaTone)
            for index in conversationLibrary.conversations.indices { conversationLibrary.conversations[index].recoverInterruptedRequest() }
            conversationLibrary = try conversationStore.save(conversationLibrary, userID: userID)
            storageError = nil; hasConversationConflict = false
            projectSelectedConversation()
        } catch {
            storageError = "Conversation history could not be opened. Existing history is kept; retry before sending another question."
        }
    }

    @discardableResult
    func saveMessages() -> Bool {
        if pendingResponse != nil { return persistPendingResponse() }
        guard let userID = activeAccountID, DIContainer.shared.authService.currentUserID == userID,
              currentConversation != nil else { return false }
        updateCurrentConversation {
            $0.messages = chatMessages; $0.draft = userMessage; $0.updatedAt = Date()
            if $0.title == "New conversation", let question = chatMessages.first(where: \.isUser) { $0.title = String(question.text.prefix(60)) }
        }
        do {
            conversationLibrary = try conversationStore.save(conversationLibrary, userID: userID)
            storageError = nil; hasConversationConflict = false
            return true
        } catch MaiaConversationStoreError.changed {
            hasConversationConflict = true
            storageError = MaiaConversationStoreError.changed.localizedDescription
            return false
        } catch {
            storageError = "This conversation could not be saved on this device. Keep this screen open and retry; existing history is kept."
            return false
        }
    }

    private func persistPendingResponse() -> Bool {
        guard let pending = pendingResponse, pending.ownerID == activeAccountID,
              pending.ownerID == DIContainer.shared.authService.currentUserID,
              pending.conversationID == currentConversation?.id,
              let index = conversationLibrary.conversations.firstIndex(where: { $0.id == pending.conversationID }),
              conversationLibrary.conversations[index].request?.id == pending.requestID else { return false }
        var candidate = conversationLibrary
        candidate.conversations[index].draft = userMessage
        guard candidate.conversations[index].acceptResponse(pending.response.content, requestID: pending.requestID,
            metadata: pending.response.metadata) else { return false }
        do {
            conversationLibrary = try conversationStore.save(candidate, userID: pending.ownerID)
            pendingResponse = nil; storageError = nil; hasConversationConflict = false
            chatMessages = currentConversation?.messages ?? chatMessages
            inlineErrorMessage = nil; retryMessage = nil; retryContextContract = nil
            HapticManager.instance.feedback(.light)
            return true
        } catch MaiaConversationStoreError.changed {
            hasConversationConflict = true; storageError = MaiaConversationStoreError.changed.localizedDescription
        } catch {
            storageError = "The answer arrived but could not be saved. Retry saving to keep it before using any action. Your question stays here."
        }
        return false
    }

    func retryConversationStorage() {
        guard hasConversationConflict else {
            if currentConversation == nil { loadMessages() } else { saveMessages() }
            return
        }
        guard let owner = activeAccountID, owner == DIContainer.shared.authService.currentUserID,
              let original = currentConversation else { return }
        do {
            guard var latest = try conversationStore.load(userID: owner) else { return }
            var recovered = MaiaConversation(title: "Recovered: " + original.title, messages: chatMessages)
            recovered.draft = userMessage; recovered.context = original.context
            recovered.communicationOverride = original.communicationOverride; recovered.request = original.request
            if let pending = pendingResponse, pending.conversationID == original.id,
               pending.ownerID == owner, pending.requestID == recovered.request?.id {
                _ = recovered.acceptResponse(pending.response.content, requestID: pending.requestID, metadata: pending.response.metadata)
            }
            recovered.recoverInterruptedRequest()
            latest.conversations.insert(recovered, at: 0); latest.selectedID = recovered.id
            conversationLibrary = try conversationStore.save(latest, userID: owner)
            pendingResponse = nil
            storageError = nil; hasConversationConflict = false
            projectSelectedConversation()
        } catch { storageError = error.localizedDescription }
    }
}
