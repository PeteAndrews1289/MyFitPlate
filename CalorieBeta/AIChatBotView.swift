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

struct ChatBubble: View {
    @Environment(\.colorScheme) var colorScheme
    var bgGreen = Color(red: 16/255, green: 20/255, blue: 21/255)
    var tbGreen = Color(red: 28/255, green: 40/255, blue: 38/255)
    
    let message: ChatMessage
    let onLogRecipe: (String) -> Void
    let onSpeak: (String) -> Void
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    private let canBeLogged: Bool

    init(message: ChatMessage, onLogRecipe: @escaping (String) -> Void, onSpeak: @escaping (String) -> Void, showAlert: Binding<Bool>, alertMessage: Binding<String>) {
        self.message = message
        self.onLogRecipe = onLogRecipe
        self.onSpeak = onSpeak
        self._showAlert = showAlert
        self._alertMessage = alertMessage
        self.canBeLogged = !message.isUser && message.text.contains("---Nutritional Breakdown---") && message.text.contains("Calories:")
    }

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.isUser { Spacer() }
                VStack(alignment: !message.isUser ? .leading : .trailing) {
                    if !message.isUser {
                        Text("Maia")
                            .padding()
                            .background(Circle().fill(colorScheme == .dark ? bgGreen : Color.backgroundSecondary ))
                            .padding(.leading, -6)
                    }
                    
                    if message.isUser {
                        Text("You")
                            .padding()
                            .background(Circle().fill(Color.brandPrimary))
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .padding(.trailing, -3)
                    }
                    
                    Text(message.text)
                        .padding()
                        .background(message.isUser ? Color.brandPrimary : Color.backgroundSecondary)
                        .cornerRadius(12)
                        .foregroundColor(message.isUser ? .white : .textPrimary)
                        .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)
                }

                if !message.isUser { Spacer() }
            }
            .padding(message.isUser ? .leading : .trailing, 40)
            
            HStack(spacing: 12) {
                if message.isUser { Spacer() }
                if !message.isUser {
                    Button(action: { onSpeak(message.text) }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(.brandPrimary)
                            .padding(.bottom, 10)
                    }
                }
                if canBeLogged {
                    Button(action: { onLogRecipe(message.text) }) {
                        Text("Log Food")
                            .appFont(size: 12, weight: .semibold)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.brandPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                if !message.isUser { Spacer() }
            }
            .padding(.horizontal, message.isUser ? 40 : 0)
        }
    }
}

private struct ChatHistoryListView: View {
    @Binding var chatMessages: [ChatMessage]
    var onLogRecipe: (String) -> Void
    var onSpeak: (String) -> Void
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
                            showAlert: $showAlert,
                            alertMessage: $alertMessage
                        )
                        .id(message.id)
                    }
                }
                .padding()
                .padding(.bottom, 120)
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
    
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var ttsManager = TTSManager.shared
    
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                ChatHistoryListView(
                    chatMessages: $chatMessages,
                    onLogRecipe: logRecipe,
                    onSpeak: ttsManager.speak,
                    showAlert: $showAlert,
                    alertMessage: $alertMessage
                )
                
                if isLoading {
                    ProgressView().padding(10)
                }

                ZStack {
                    ChatBoxShape()
                        .fill(colorScheme == .dark ? bgGreen : Color.backgroundSecondary)
                        .shadow(color: .black.opacity(0.1), radius: 5, y: -2)

                    HStack(spacing: 15) {
                        TextField("Ask Maia anything...", text: $userMessage, axis: .vertical)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(colorScheme == .dark ? Color(white: 0.2) : Color.white)
                            .clipShape(Capsule())
                            .onSubmit(sendMessage)
                        
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.brandPrimary)
                        }
                        .disabled(userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
                }
                .frame(height: 120)
            }
        }
        .navigationTitle("Maia")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onTapGesture {
            hideKeyboard()
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

    private var remainingCalories: Double {
        let logDate = dailyLogService.activelyViewedDate
        let relevantLog = dailyLogService.currentDailyLog != nil && Calendar.current.isDate(dailyLogService.currentDailyLog!.date, inSameDayAs: logDate) ? dailyLogService.currentDailyLog : nil
        let total = relevantLog?.totalCalories() ?? 0
        let goal = goalSettings.calories ?? 2000
        return max(0, goal - total)
    }
    
    private var remainingProtein: Double {
        let logDate = dailyLogService.activelyViewedDate
        let relevantLog = dailyLogService.currentDailyLog != nil && Calendar.current.isDate(dailyLogService.currentDailyLog!.date, inSameDayAs: logDate) ? dailyLogService.currentDailyLog : nil
        let total = relevantLog?.totalMacros().protein ?? 0
        return max(0, goalSettings.protein - total)
    }
    
    private var remainingFats: Double {
        let logDate = dailyLogService.activelyViewedDate
        let relevantLog = dailyLogService.currentDailyLog != nil && Calendar.current.isDate(dailyLogService.currentDailyLog!.date, inSameDayAs: logDate) ? dailyLogService.currentDailyLog : nil
        let total = relevantLog?.totalMacros().fats ?? 0
        return max(0, goalSettings.fats - total)
    }
    
    private var remainingCarbs: Double {
        let logDate = dailyLogService.activelyViewedDate
        let relevantLog = dailyLogService.currentDailyLog != nil && Calendar.current.isDate(dailyLogService.currentDailyLog!.date, inSameDayAs: logDate) ? dailyLogService.currentDailyLog : nil
        let total = relevantLog?.totalMacros().carbs ?? 0
        return max(0, goalSettings.carbs - total)
    }

    func sendMessage() {
        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        let userMsg = ChatMessage(id: UUID(), text: trimmedMessage, isUser: true)
        chatMessages.append(userMsg)
        
        let msgToSend = userMessage
        userMessage = ""
        isLoading = true
        hideKeyboard()

        fetchGPT3Response(for: msgToSend) { aiResponse in
            let aiMsg = ChatMessage(id: UUID(), text: aiResponse, isUser: false)
            chatMessages.append(aiMsg)
            isLoading = false
        }
    }

    func fetchGPT3Response(for message: String, completion: @escaping (String) -> Void) {
        let apiKey = getAPIKey()
        guard !apiKey.isEmpty, apiKey != "wtv" else {
            completion("Error: API Key missing.")
            return
        }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        You are a helpful AI assistant for a fitness app called MyFitPlate. Your name is Maia.
        When a user asks for nutritional information (e.g., "calories in an apple"), your response MUST be in the following format:
        1. Start with a brief, friendly sentence.
        2. On a new line, write the header "---Nutritional Breakdown---".
        3. On subsequent new lines, list "Calories: <value>", "Protein: <value>g", "Carbs: <value>g", and "Fats: <value>g". Include other relevant micronutrients like Sodium, Potassium, and key vitamins if available.
        This format is critical for the app to function. Do not deviate from it.
        When a user asks for a meal plan and grocery list, use the following format:
        Start with "---Meal Plan---". List each day (e.g., "Day 1:") followed by meals.
        Then, on a new line, start with "---Grocery List---". List each item with quantity and unit (e.g., "Chicken Breast: 2 lbs").
        **User's Remaining Goals for Today:**
        - Calories: \(String(format: "%.0f", self.remainingCalories)) cal
        - Protein: \(String(format: "%.0f", self.remainingProtein)) g
        - Fats: \(String(format: "%.0f", self.remainingFats)) g
        - Carbs: \(String(format: "%.0f", self.remainingCarbs)) g
        """
        
        var messagesForAPI: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        
        let history = chatMessages.suffix(6)
        for chatMessage in history {
            if !chatMessage.text.isEmpty {
                messagesForAPI.append(["role": chatMessage.isUser ? "user" : "assistant", "content": chatMessage.text])
            }
        }
        
        messagesForAPI.append(["role": "user", "content": message])

        let requestBody: [String: Any] = ["model": "gpt-4o-mini", "messages": messagesForAPI, "max_tokens": 1000, "temperature": 0.5]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion("Error: Failed to serialize request.")
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    completion("Error: Network failed - \(error.localizedDescription)")
                    return
                }
                guard let data = data else {
                    completion("Error: No data.")
                    return
                }
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let errDict = json["error"] as? [String: Any], let errMsg = errDict["message"] as? String {
                            completion("Error: \(errMsg)")
                        } else if let choices = json["choices"] as? [[String: Any]], let first = choices.first, let msg = first["message"] as? [String: Any], let content = msg["content"] as? String {
                            completion(content.trimmingCharacters(in: .whitespacesAndNewlines))
                        } else {
                            completion("Error: Invalid API response.")
                        }
                    } else {
                        completion("Error: Cannot parse response.")
                    }
                } catch {
                    completion("Error: Failed to parse response - \(error.localizedDescription)")
                }
            }
        }.resume()
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
        dailyLogService.addMealToCurrentLog(for: userID, mealName: mealType, foodItems: [loggedFoodItem])
        let haptic = UINotificationFeedbackGenerator(); haptic.notificationOccurred(.success); alertMessage = "\(foodName) logged!"; showAlert = true
        Task { @MainActor in self.achievementService.checkFeatureUsedAchievement(userID: userID, featureType: .aiRecipeLogged) }
    }
    
    private func parseNutrient(from text: String, for nutrient: String) -> Double? {
        do {
            let regex = try NSRegularExpression(pattern: "\(nutrient):\\s*([\\d.]+)", options: .caseInsensitive)
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: nsRange),
                let range = Range(match.range(at: 1), in: text) {
                return Double(text[range])
            }
        } catch {}
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
