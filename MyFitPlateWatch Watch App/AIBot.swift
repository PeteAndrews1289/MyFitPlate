import SwiftUI
import WatchKit
import AVFoundation

struct AIBot: View {
    @State private var userInput = ""
    @State private var aiResponse = ""
    @State private var showingInput = false
    @EnvironmentObject var appDelegate: AppDelegate

    private let synthesizer = AVSpeechSynthesizer()
    
    var body: some View {
        NavigationStack {
            ScrollView{
                VStack(spacing: 12) {
                    Text("Recipe Bot")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
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
                         - Calories: \(Int(appDelegate.goalCal - appDelegate.userCal)) kcal
                         - Protein: \(Int(appDelegate.totalProt - appDelegate.userProt)) g
                         - Fats: \(Int(appDelegate.totalFat - appDelegate.userFat)) g
                         - Carbs: \(Int(appDelegate.totalCarb - appDelegate.userCarb)) g

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
