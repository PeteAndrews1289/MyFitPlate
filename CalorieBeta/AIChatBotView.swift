import SwiftUI
import FirebaseFirestore
import FirebaseAuth

func capitalizedFirstLetter(of string: String) -> String {
    guard let first = string.first else { return "" }
    return first.uppercased() + string.dropFirst()
}

struct AIChatbotView: View {
    @State private var userMessage = ""
    @State private var chatMessages: [ChatMessage] = []
    @State private var isLoading = false
    @Binding var selectedTab: Int
    var chatContext: String?

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @Environment(\.colorScheme) var colorScheme
    @State private var showAlert = false
    @State private var alertMessage = ""
    private let bottomScrollID = "bottomInputArea"

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

    private var remainingGoalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remaining Goals for \(dailyLogService.dateFormatter.string(from: dailyLogService.activelyViewedDate))").font(.title3).fontWeight(.semibold).foregroundColor(colorScheme == .dark ? .white : .black)
            Text("Calories: \(String(format: "%.0f", remainingCalories)) cal").font(.subheadline).foregroundColor(.gray)
            Text("Protein: \(String(format: "%.0f", remainingProtein)) g").font(.subheadline).foregroundColor(.gray)
            Text("Fats: \(String(format: "%.0f", remainingFats)) g").font(.subheadline).foregroundColor(.gray)
            Text("Carbs: \(String(format: "%.0f", remainingCarbs)) g").font(.subheadline).foregroundColor(.gray)
        }.padding().background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white).cornerRadius(15).shadow(radius: 2)
    }

    private var chatHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chat History").font(.title3).fontWeight(.semibold).foregroundColor(colorScheme == .dark ? .white : .black)
            ChatHistoryListView(chatMessages: $chatMessages, onLogRecipe: logRecipe, showAlert: $showAlert, alertMessage: $alertMessage)
                .frame(maxHeight: 300)
        }.padding().background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white).cornerRadius(15).shadow(radius: 2)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Ask Maia for nutritional info...", text: $userMessage)
                    .textFieldStyle(RoundedBorderTextFieldStyle()).padding().submitLabel(.done).onSubmit { sendMessage() }
                Button(action: sendMessage) { Image(systemName: "paperplane.fill").font(.title2).padding().foregroundColor(.white) }.disabled(isLoading || userMessage.isEmpty).background(Color.accentColor).clipShape(Circle())
            }.padding().background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white).cornerRadius(15).shadow(radius: 2)
        }.id(bottomScrollID)
    }

    var body: some View {
        ScrollViewReader { outerProxy in
            ScrollView {
                VStack(spacing: 16) {
                    remainingGoalsSection
                    chatHistorySection
                    inputSection
                    
                    Text("AI-generated content may be inaccurate. Nutritional information is an estimate and not a substitute for professional medical advice.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 10)
                }
                .padding(.vertical)
            }
            .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
            .navigationTitle("Maia")
            .onTapGesture { hideKeyboard() }
            .onAppear {
                loadMessages()

                if let userID = Auth.auth().currentUser?.uid {
                    dailyLogService.fetchLog(for: userID, date: dailyLogService.activelyViewedDate) { _ in }
                }
                
                if chatMessages.isEmpty {
                    let welcomeMessage = """
                    Hello! I'm Maia, your personal nutrition assistant.

                    You can ask me for:
                    - Nutritional info for any food (e.g., "calories in an apple")
                    - A recipe with nutrition estimates (e.g., "healthy chicken breast recipe")

                    How can I help you today?
                    """
                    let initialMessage = ChatMessage(id: UUID(), text: welcomeMessage, isUser: false)
                    chatMessages.append(initialMessage)
                }
                
                outerProxy.scrollTo(bottomScrollID, anchor: .bottom)
            }
            .onDisappear(perform: saveMessages)
            .onReceive(appState.$pendingChatPrompt) { prompt in
                if let prompt = prompt {
                    userMessage = prompt
                    sendMessage()
                    appState.pendingChatPrompt = nil
                }
            }
            .alert(isPresented: $showAlert) { Alert(title: Text("Notification"), message: Text(alertMessage), dismissButton: .default(Text("OK"))) }
        }
    }

    func sendMessage() { guard !userMessage.isEmpty else { return }; let userMsg = ChatMessage(id: UUID(), text: userMessage, isUser: true); chatMessages.append(userMsg); let msgToSend = userMessage; userMessage = ""; isLoading = true; fetchGPT3Response(for: msgToSend) { aiResponse in let aiMsg = ChatMessage(id: UUID(), text: aiResponse, isUser: false); chatMessages.append(aiMsg); isLoading = false } }

    func fetchGPT3Response(for message: String, completion: @escaping (String) -> Void) {
        let apiKey = getAPIKey()
        guard apiKey != "YOUR_API_KEY", !apiKey.isEmpty else { completion("Error: API Key missing."); isLoading = false; return }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); request.addValue("application/json", forHTTPHeaderField: "Content-Type")

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
        - Calories: \(String(format: "%.0f", remainingCalories)) cal
        - Protein: \(String(format: "%.0f", remainingProtein)) g
        - Fats: \(String(format: "%.0f", remainingFats)) g
        - Carbs: \(String(format: "%.0f", remainingCarbs)) g
        """
        
        var messagesForAPI: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        
        let history = chatMessages.suffix(6)
        for chatMessage in history {
            if !chatMessage.text.isEmpty {
                messagesForAPI.append(["role": chatMessage.isUser ? "user" : "assistant", "content": chatMessage.text])
            }
        }
        
        messagesForAPI.append(["role": "user", "content": message])

        let requestBody: [String: Any] = ["model": "gpt-3.5-turbo", "messages": messagesForAPI, "max_tokens": 1000, "temperature": 0.5]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else { completion("Error: Failed to serialize request."); isLoading = false; return }
        request.httpBody = httpBody
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion("Error: Network failed - \(error.localizedDescription)"); return }
                guard let data = data else { completion("Error: No data."); return }
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let errDict = json["error"] as? [String: Any], let errMsg = errDict["message"] as? String { completion("Error: \(errMsg)") }
                        else if let choices = json["choices"] as? [[String: Any]], let first = choices.first, let msg = first["message"] as? [String: Any], let content = msg["content"] as? String {
                            completion(content.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        else { completion("Error: Invalid API response.") }
                    } else { completion("Error: Cannot parse response.") }
                } catch { completion("Error: Failed to parse response - \(error.localizedDescription)") }
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
        } catch {
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
    private func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    
    private func loadMessages() {
        guard let userID = Auth.auth().currentUser?.uid else {
            self.chatMessages = []
            return
        }
        let key = "chatHistory_\(userID)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decodedMessages = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            self.chatMessages = decodedMessages
        } else {
            self.chatMessages = []
        }
    }
    
    private func saveMessages() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let key = "chatHistory_\(userID)"
        let max = 8
        let messagesToSave = Array(chatMessages.suffix(max))
        
        if let encoded = try? JSONEncoder().encode(messagesToSave) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}

private struct ChatHistoryListView: View {
    @Binding var chatMessages: [ChatMessage]
    var onLogRecipe: (String) -> Void
    @Binding var showAlert: Bool
    @Binding var alertMessage: String

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(chatMessages) { message in
                        ChatBubble(message: message, onLogRecipe: onLogRecipe, showAlert: $showAlert, alertMessage: $alertMessage)
                            .id(message.id)
                    }
                }
                .onChange(of: chatMessages) { _ in
                    if let lastId = chatMessages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
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

struct ChatMessage: Identifiable, Codable, Equatable { let id: UUID; let text: String; let isUser: Bool;  }

struct ChatBubble: View {
     let message: ChatMessage
     let onLogRecipe: (String) -> Void
     @Environment(\.colorScheme) var colorScheme
     @Binding var showAlert: Bool
     @Binding var alertMessage: String
     private let canBeLogged: Bool
     
     init(message: ChatMessage, onLogRecipe: @escaping (String) -> Void, showAlert: Binding<Bool>, alertMessage: Binding<String>) {
        self.message = message
        self.onLogRecipe = onLogRecipe
        self._showAlert = showAlert
        self._alertMessage = alertMessage
        self.canBeLogged = !message.isUser && message.text.contains("---Nutritional Breakdown---") && message.text.contains("Calories:")
     }
     
     var body: some View {
         VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
             HStack {
                 if message.isUser { Spacer() }
                 Text(message.text)
                     .padding().background(message.isUser ? Color.accentColor : Color.gray.opacity(0.2)).cornerRadius(12)
                     .foregroundColor(message.isUser ? .white : (colorScheme == .dark ? .white : .black))
                     .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)
                 if !message.isUser { Spacer() }
             }.padding(message.isUser ? .leading : .trailing, 40)
             
             HStack {
                 if canBeLogged {
                     Button(action: { onLogRecipe(message.text) }) {
                         Text("Log Food").font(.caption).fontWeight(.semibold).padding(.vertical, 4).padding(.horizontal, 8)
                             .background(Color.accentColor).foregroundColor(.white).cornerRadius(8)
                     }
                 }
             }
             .padding(.leading, message.isUser ? 0 : 0)
             .padding(.trailing, message.isUser ? 40 : 0)
         }
     }
}
