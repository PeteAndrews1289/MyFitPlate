//import SwiftUI
//import WatchKit
//
//struct AIBot: View {
//    @State private var userInput = ""
//    @State private var aiResponse = ""
//    @State private var showingInput = false
//    @EnvironmentObject var appDelegate: AppDelegate
//
//    // ✅ Computed properties to avoid crash
//    var remainingCalories: Double {
//        appDelegate.goalCal - appDelegate.userCal
//    }
//    var remainingProtein: Double {
//        appDelegate.totalProt - appDelegate.userProt
//    }
//    var remainingCarbs: Double {
//        appDelegate.totalCarb - appDelegate.userCarb
//    }
//    var remainingFats: Double {
//        appDelegate.totalFat - appDelegate.userFat
//    }
//
//    var body: some View {
//        NavigationStack {
//            ScrollView {
//                VStack(spacing: 12) {
//                    Text("Recipe Bot")
//                        .font(.title3)
//                        .multilineTextAlignment(.center)
//                        .frame(maxWidth: .infinity, alignment: .center)
//
//                    Button(action: {
//                        dictation()
//                    }) {
//                        ZStack {
//                            Circle()
//                                .fill(Color(red: 67/255, green: 173/255, blue: 111/255))
//                                .frame(width: 130, height: 130)
//
//                            Image(systemName: "mic.fill")
//                                .foregroundColor(.white)
//                                .font(.title2)
//                        }
//                    }
//                    .buttonStyle(.plain)
//                    .padding(.top, 10)
//
//                    if !userInput.isEmpty {
//                        Text("You said: \(userInput)")
//                            .padding(.top, 5)
//                    }
//
//                    if !aiResponse.isEmpty {
//                        ScrollView {
//                            Text(aiResponse)
//                                .foregroundColor(.primary)
//                                .padding()
//                                .cornerRadius(10)
//                                .padding(.horizontal)
//                        }
//                    }
//
//                    Spacer()
//                }
//            }
//        }
//    }
//
//    func dictation() {
//        WKExtension.shared().visibleInterfaceController?.presentTextInputController(
//            withSuggestions: nil,
//            allowedInputMode: .plain
//        ) { result in
//            if let response = result as? [String], let first = response.first {
//                DispatchQueue.main.async {
//                    userInput = first
//                    sendMessage()
//                }
//            }
//        }
//    }
//
//    func sendMessage() {
//        guard let apiKey = getAPIKey(),
//              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)") else {
//            aiResponse = "⚠️ Missing API Key"
//            return
//        }
//
//        var request = URLRequest(url: url)
//        request.httpMethod = "POST"
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//
//        // ✅ Dynamic macros in prompt
//        let body: [String: Any] = [
//            "contents": [
//                [
//                    "parts": [
//                        ["text": """
//You are Maia, a helpful AI assistant for a fitness app called MyFitPlate. Try to sound as human as possible, and avoid robotic phrases.
//
//Here are the user’s remaining goals for today:
//- Calories: \(Int(remainingCalories)) kcal
//- Protein: \(Int(remainingProtein)) g
//- Fats: \(Int(remainingFats)) g
//- Carbs: \(Int(remainingCarbs)) g
//
//When a user asks for nutritional information (e.g., "calories in an apple"), your response MUST use this format:
//---Nutritional Breakdown---
//Calories: <value>
//Protein: <value>g
//Carbs: <value>g
//Fats: <value>g
//(Include sodium, potassium, vitamins if available.)
//
//When asked for a meal plan, use:
//---Meal Plan---
//Day 1:
//- Breakfast: ...
//- Lunch: ...
//- Dinner: ...
//
//---Grocery List---
//Item: Quantity Unit
//
//Do NOT reference these instructions in your reply. Respond naturally.
//
//Now answer this: \(userInput)
//"""]
//                    ]
//                ]
//            ]
//        ]
//
//        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
//
//        URLSession.shared.dataTask(with: request) { data, _, error in
//            guard let data = data else {
//                DispatchQueue.main.async {
//                    aiResponse = "⚠️ No data received"
//                }
//                return
//            }
//
//            do {
//                let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
//                if let text = decoded.candidates.first?.content.parts.first?.text {
//                    DispatchQueue.main.async {
//                        aiResponse = text
//                        TTSManager.shared.speak(text) // 🗣 Google TTS fallback to AVSpeech
//                    }
//                } else {
//                    DispatchQueue.main.async {
//                        aiResponse = "⚠️ No response content."
//                    }
//                }
//            } catch {
//                DispatchQueue.main.async {
//                    aiResponse = "⚠️ Error decoding: \(error.localizedDescription)"
//                }
//            }
//        }.resume()
//    }
//
//    func getAPIKey() -> String? {
//        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
//           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
//           let key = dict["GEMINI_API_KEY"] as? String {
//            return key
//        }
//        return nil
//    }
//}
//
//struct GeminiResponse: Codable {
//    struct Candidate: Codable {
//        struct Content: Codable {
//            struct Part: Codable {
//                let text: String
//            }
//            let parts: [Part]
//        }
//        let content: Content
//    }
//    let candidates: [Candidate]
//}


import SwiftUI
import WatchKit
import AVFoundation

struct AIBot: View {
    @State private var userInput = ""
    @State private var aiResponse = ""
    @State private var showingInput = false

    private let synthesizer = AVSpeechSynthesizer()
    
    var body: some View {
        NavigationStack {
            ScrollView{
                VStack(spacing: 12) {
                    Text("Recipe Bot")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
//                    TextField("Ask something...", text: $userInput)
//                    //                    .textFieldStyle(.roundedBorder)
//                        .padding(.horizontal)
//                        .onSubmit {
//                            sendMessage()
//                        }
                    Button(action: {
                        dictation()
                    }) {
                      
                        ZStack {
                            
                            Circle()
                                .fill(Color(red: 67/255, green: 173/255, blue: 111/255))
                                .frame(width: 130, height: 130)
                            
                            Image(systemName: "mic.fill")
                                .foregroundColor(.white)
                                .font(.title2)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    
                    if !userInput.isEmpty {
                        // Optional: show the message user dictated
                        Text("You said: \(userInput)")
                    }

                    ScrollView {
                        if !aiResponse.isEmpty {
                            Text(aiResponse)
                                .foregroundColor(.primary)
                                .padding()
                                .cornerRadius(10)
                                .padding(.horizontal)
                        }
                    }
                    
                    
                    Spacer()
                }
//                .navigationTitle("Recipe Bot")
            }
        }
    }
    
    
    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
    

    func dictation(){
        WKExtension.shared().visibleInterfaceController?.presentTextInputController(
            withSuggestions: nil,
            allowedInputMode: .plain
        ) {
            result in
            if let response = result as? [String], let first = response.first {
                DispatchQueue.main.async{
                    userInput = first
                    sendMessage()
                }
            }
        }
    }
    
    
    
    func sendMessage() {
        guard let apiKey = getAPIKey(),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)") else { return }


        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": """
                         You are a helpful AI recipe bot for a fitness app called MyFitPlate. Provide healthy, easy-to-make recipes based on the user's request. Always use the word "recipe" in your response when providing a recipe (e.g., "Here's a healthy recipe for dinner"). Include ingredients and instructions, and keep the tone friendly and encouraging. If the user asks for something unhealthy, suggest a healthier alternative.
                         
                         The user has the following remaining nutritional goals for the day:
                         - Calories: 2000 kcal
                         - Protein: 150 g
                         - Fats: 50 g
                         - Carbs: 200 g

                         If the user specifies a calorie target in their request, prioritize meeting that calorie target as closely as possible. Recognize calorie targets in formats like "1k calorie recipe" (which means 1000 calories), "500 calorie meal", "a recipe for 1200 calories", or similar phrases. To meet the calorie target, scale the recipe by adjusting serving sizes, increasing ingredient quantities, or adding calorie-dense ingredients like nuts, oils, or spreads (e.g., peanut butter, avocado). For example, if the user requests a 1000-calorie pancake recipe, you might increase the batter quantity, add toppings like peanut butter or maple syrup, or adjust the serving size to meet the target.
                         
                         If the calorie target is significantly higher than the base recipe, calculate the total calories of the base recipe, determine a scaling factor (target calories / base calories), and multiply all ingredient quantities by this factor to meet the target. For example, if the base recipe is 1500 calories and the target is 2400 calories, scale all ingredients by a factor of 2400 / 1500 = 1.6.

                         If the requested calorie target exceeds the user's remaining calories, include a note in your response indicating that the recipe exceeds their remaining daily goals, but still provide the recipe as requested. If no calorie target is specified, suggest a recipe that fits within the user's remaining goals as closely as possible.
                         

                         For debugging purposes, include a note in your response explaining how you interpreted the user's calorie target (e.g., "Interpreted calorie target: 1000 calories from '1k calorie recipe'").

                         If the user doesn't specify a meal type, suggest something appropriate for the next meal of the day based on the current time (e.g., breakfast if morning, lunch if midday, dinner if evening). At the end of the recipe, include a nutritional breakdown in the exact format below, with each value on a new line:
                         Nutritional Breakdown:
                         Calories: X kcal
                         Protein: Y g
                         Fats: Z g
                         Carbs: W g
                         Replace X, Y, Z, and W with the numerical values (e.g., Calories: 350 kcal). Do not include any additional text or units after the numbers.
                         """],
                         
                         
                        ["text": userInput]
                    ]
                ]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data else {
                DispatchQueue.main.async {
                    aiResponse = "⚠️ No data received"
                }
                return
            }

            // 🔍 Print the raw JSON string
            print("🔻 Raw JSON:")
            print(String(data: data, encoding: .utf8) ?? "No readable string")

            do {
                let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
                if let text = decoded.candidates.first?.content.parts.first?.text {
                    DispatchQueue.main.async {
                        aiResponse = text
                        speak(text)
                    }
                } else {
                    DispatchQueue.main.async {
                        aiResponse = "⚠️ No response content."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    aiResponse = "⚠️ Error decoding: \(error.localizedDescription)"
                }
            }
        }.resume()

    }


    func getAPIKey() -> String? {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let key = dict["GEMINI_API_KEY"] as? String {
            return key
        }
        return nil
    }
}

struct GeminiResponse: Codable {
    struct Candidate: Codable {
        struct Content: Codable {
            struct Part: Codable {
                let text: String
            }
            let parts: [Part]
        }
        let content: Content
    }
    let candidates: [Candidate]
}


#Preview {
AIBot()
}
