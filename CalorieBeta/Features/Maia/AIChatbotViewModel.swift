import SwiftUI

@MainActor
class AIChatbotViewModel: ObservableObject {
    @Published var userMessage = ""
    @Published var chatMessages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var showingClearChatConfirmation = false
    
    var chatContext: String?
    
    // Service references
    var dailyLogService: DailyLogService?
    var goalSettings: GoalSettings?
    var achievementService: AchievementService?
    var mealPlannerService: MealPlannerService?
    var healthKitViewModel: HealthKitViewModel?
    
    func setupView() {
        loadMessages()
        if let userID = DIContainer.shared.authService.currentUserID {
            dailyLogService?.fetchLog(for: userID, date: dailyLogService?.activelyViewedDate ?? Date()) { _ in }
        }
        if chatMessages.isEmpty {
            let initialMessage = ChatMessage(id: UUID(), text: welcomeMessage(), isUser: false)
            chatMessages.append(initialMessage)
        }
    }
    
    func clearChat() {
        chatMessages.removeAll()
        chatMessages.append(ChatMessage(id: UUID(), text: welcomeMessage(), isUser: false))
        saveMessages()
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
        relevantDailyLog?.waterTracker?.goalOunces ?? goalSettings?.waterGoal ?? 100
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
            - Water logged: \(Int(waterOunces.rounded())) oz of \(Int(waterGoal.rounded())) oz target
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
        guard !trimmedMessage.isEmpty else { return }
        let mayShareHealthData = canShareHealthDataWithAI
        let effectiveContract = (contextContract ?? .generalChat(includeHealthKit: mayShareHealthData))
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

        let msgToSend = userMessage
        userMessage = ""
        isLoading = true

        fetchGPT3Response(for: msgToSend, contextContract: effectiveContract) { [weak self] aiResponse in
            guard let self = self else { return }
            let aiMsg = ChatMessage(id: UUID(), text: aiResponse, isUser: false)
            self.chatMessages.append(aiMsg)
            self.isLoading = false
            HapticManager.instance.feedback(.light)
        }
    }
    
    func fetchGPT3Response(
        for message: String,
        contextContract: MaiaContextContract,
        completion: @escaping (String) -> Void
    ) {
        let systemPrompt = """
        You are Maia, the personal nutrition and training coach inside MyFitPlate.
        Your style is warm, concise, practical, and specific to the user's logged day. Avoid generic wellness filler.
        Do not diagnose medical conditions or present estimates as clinical truth.
        Respect the user's coaching preferences in the context. If reminder style is Minimal, be brief. If Direct, be crisp and action-oriented. If Gentle, be encouraging without being vague.
        \(MaiaConversationStyle.promptInstructions(for: goalSettings?.maiaTone))
        If the nutrition audit says calories and macros meaningfully disagree, mention that logged calories remain official but the item should be reviewed before making precise calorie-budget claims.
        Respect the user's calorie target. Training fuel should be planned before hard sessions and kept inside the user's chosen target unless the user explicitly changes the target. If the user is already over target, do not give it a special mode label, do not celebrate it, and do not frame accidental over-target intake as performance fuel; give a neutral review and the next best on-target choice.
        \(contextContract.promptSummary)

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
        The user enters weight in \(BodyUnits.weightUnit(metric: UserDefaults.standard.bool(forKey: "useMetricBodyUnits"))). ALWAYS return "weightPounds" in POUNDS — if the stated weight is in kilograms, convert it (1 kg = 2.20462 lb).
        ```json
        {
          "type": "log_weight",
          "weightPounds": 150.5
        }
        ```

        You may include conversational text BEFORE the JSON block. Do not include any text after the JSON block.
        If data is missing, say what assumption you are making.
        For your own AI estimates, keep calories reasonably consistent with protein*4 + carbs*4 + fats*9. Do not invent exact precision for restaurant or packaged foods.

        \(promptContextSummary(for: contextContract))
        \(chatContext.map { "Additional context: \($0)" } ?? "")
        """

        var messagesForAPI: [[String: Any]] = [["role": "system", "content": systemPrompt]]

        let history = chatMessages.dropLast().suffix(6)
        for chatMessage in history where !chatMessage.text.isEmpty {
            messagesForAPI.append(["role": chatMessage.isUser ? "user" : "assistant", "content": chatMessage.text])
        }

        messagesForAPI.append(["role": "user", "content": message])

        Task { @MainActor in
            let result = await DIContainer.shared.aiService.performRequest(
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
    
    // MARK: - Action Handling

    func logRecipe(recipeText: String) {
        guard let userID = DIContainer.shared.authService.currentUserID else { alertMessage = "Not logged in."; showAlert = true; return }
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
            .withAIEstimateSource(.aiChat, sourceName: "Maia Chat")
        let mealType = determineMealType()
        dailyLogService?.addMealToLog(for: userID, date: dailyLogService?.activelyViewedDate ?? Date(), mealName: mealType, foodItems: [loggedFoodItem], source: "ai_chat")
        let haptic = UINotificationFeedbackGenerator(); haptic.notificationOccurred(.success); alertMessage = "\(foodName) logged!"; showAlert = true
        Task { @MainActor in self.achievementService?.checkFeatureUsedAchievement(userID: userID, featureType: .aiRecipeLogged) }
    }

    func handleMaiaAction(_ action: MaiaAction) {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            alertMessage = "Not logged in."
            showAlert = true
            return
        }

        switch action {
        case .generateMealPlan:
            Task {
                guard let mealPlannerService = self.mealPlannerService, let goalSettings = self.goalSettings else { return }
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
                        self.alertMessage = "Meal Plan generated! Check the Meal Plan tab."
                    } else {
                        self.alertMessage = "Failed to generate meal plan. Please try again."
                    }
                    self.showAlert = true
                }
            }
        case .logWorkout(let exerciseName, let durationMinutes, let caloriesBurned):
            dailyLogService?.addWorkoutToCurrentLog(
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
            dailyLogService?.addWaterToCurrentLog(for: userID, amount: amountOunces, goalOunces: goalSettings?.waterGoal ?? 100)
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
            goalSettings?.updateUserWeight(weightPounds)
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            let useMetric = UserDefaults.standard.bool(forKey: "useMetricBodyUnits")
            alertMessage = "Weight updated to \(String(format: "%.1f", BodyUnits.weightDisplayValue(lbs: weightPounds, metric: useMetric))) \(BodyUnits.weightUnit(metric: useMetric))!"
            showAlert = true
        }
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
    
    private func loadMessages() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let key = "chatHistory_\(userID)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decodedMessages = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            self.chatMessages = decodedMessages
        }
    }

    func saveMessages() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let key = "chatHistory_\(userID)"
        let max = 12
        let messagesToSave = Array(chatMessages.suffix(max))

        if let encoded = try? JSONEncoder().encode(messagesToSave) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
