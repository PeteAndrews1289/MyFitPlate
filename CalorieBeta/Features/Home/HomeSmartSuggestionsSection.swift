import SwiftUI
import FirebaseAuth

struct HomeSmartSuggestionsSection: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    var selectedDate: Date

    var body: some View {
VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Smart Suggestions")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Log recent meals with 1 tap.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(dailyLogService.smartSuggestions) { item in
                        Button(action: {
                            HapticManager.instance.notification(.success)
                            if let userId = Auth.auth().currentUser?.uid {
                                // Assume adding it to the current time context meal
                                let hour = Calendar.current.component(.hour, from: Date())
                                let mealType: String
                                if hour < 10 { mealType = "Breakfast" }
                                else if hour < 15 { mealType = "Lunch" }
                                else if hour < 21 { mealType = "Dinner" }
                                else { mealType = "Snacks" }

                                dailyLogService.addFoodToLog(for: userId, date: selectedDate, mealName: mealType, foodItem: item, source: "smart_suggestion")
                            }
                        }) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(FoodEmojiMapper.getEmoji(for: item.name))
                                    .appFont(size: 28)

                                Text(item.name.capitalized)
                                    .appFont(size: 14, weight: .bold)
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                Text("\(Int(item.calories)) cal")
                                    .appFont(size: 12, weight: .medium)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                            .padding(12)
                            .frame(width: 120, alignment: .leading)
                            .background(Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: 520)

}
}
