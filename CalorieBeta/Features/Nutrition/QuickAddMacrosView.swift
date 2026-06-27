import SwiftUI
import FirebaseAuth

struct QuickAddMacrosView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService

    let selectedMealType: String
    let targetDate: Date

    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fats: String = ""

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Macros").appFont(size: 13, weight: .semibold)) {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("0", text: $calories)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Protein (g)")
                        Spacer()
                        TextField("0", text: $protein)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Carbs (g)")
                        Spacer()
                        TextField("0", text: $carbs)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Fats (g)")
                        Spacer()
                        TextField("0", text: $fats)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .appFont(size: 13)
                    }
                }
            }
            .navigationTitle("Quick Add Macros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveMacros()
                    }
                    .fontWeight(.bold)
                    .disabled(isSaving || (calories.isEmpty && protein.isEmpty && carbs.isEmpty && fats.isEmpty))
                }
            }
        }
    }

    private func saveMacros() {
        guard let userID = Auth.auth().currentUser?.uid else {
            errorMessage = "Not logged in."
            return
        }

        let cal = Double(calories) ?? 0
        let p = Double(protein) ?? 0
        let c = Double(carbs) ?? 0
        let f = Double(fats) ?? 0

        // If calories is 0 but macros exist, calculate them
        let finalCalories = cal > 0 ? cal : (p * 4 + c * 4 + f * 9)

        let newFood = FoodItem(
            id: UUID().uuidString,
            name: "Quick Add Macros",
            calories: finalCalories,
            protein: p,
            carbs: c,
            fats: f,
            servingSize: "1 Custom Entry",
            servingWeight: 1,
            timestamp: Date()
        )

        isSaving = true

        dailyLogService.fetchLog(for: userID, date: targetDate) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(var log):
                    if let index = log.meals.firstIndex(where: { $0.name == selectedMealType }) {
                        log.meals[index].foodItems.append(newFood)
                    } else {
                        let newMeal = Meal(name: selectedMealType, foodItems: [newFood])
                        log.meals.append(newMeal)
                    }
                    dailyLogService.updateDailyLog(for: userID, updatedLog: log) { success in
                        isSaving = false
                        if success {
                            dismiss()
                        } else {
                            errorMessage = "Failed to save macros."
                        }
                    }
                case .failure(let error):
                    isSaving = false
                    errorMessage = "Failed to fetch log: \(error.localizedDescription)"
                }
            }
        }
    }
}


struct MenuScannerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var goalSettings: GoalSettings
    
    @State private var capturedImage: UIImage? = nil
    @State private var showingCamera = false
    @State private var isProcessing = false
    @State private var recommendedMeals: [FoodItem] = []
    @State private var errorMessage: String? = nil
    @State private var remainingCaloriesSnapshot: Double = 0
    
    private let aiModel = MLImageModel()
    
    var body: some View {
        NavigationStack {
            VStack {
                if isProcessing {
                    loadingState
                } else if !recommendedMeals.isEmpty {
                    resultsState
                } else {
                    VStack(spacing: 24) {
                        Image(systemName: "menucard")
                            .appFont(size: 60)
                            .foregroundColor(.brandPrimary)
                        
                        Text("Menu Matchmaker")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Snap a photo of any restaurant menu. We'll find the best options that fit your remaining macros.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 32)
                        
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        Button(action: {
                            showingCamera = true
                        }) {
                            Label("Scan Menu", systemImage: "camera")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.brandPrimary)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal, 32)
                        .onChange(of: capturedImage) { _, newValue in
                            if let uiImage = newValue {
                                processImage(uiImage)
                            }
                        }
                        .sheet(isPresented: $showingCamera) {
                            ImagePicker(sourceType: .camera) { uiImage in
                                capturedImage = uiImage
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Menu Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(.brandPrimary)
            Text("Reading the menu and matching your macros…")
                .appFont(size: 15, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsState: some View {
        let remaining = remainingCaloriesSnapshot
        let fittingCount = recommendedMeals.filter { remaining > 0 && $0.calories <= remaining }.count
        return ScrollView {
            VStack(spacing: 12) {
                if remaining > 0 && fittingCount == 0 {
                    menuBudgetBanner(remaining: remaining)
                }

                HStack {
                    Text(remaining > 0
                         ? "5 picks · \(fittingCount) fit your remaining \(Int(remaining)) cal"
                         : "Top picks from this menu")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Spacer()
                }
                .padding(.horizontal, 4)

                ForEach(recommendedMeals) { meal in
                    Button { logMeal(meal) } label: {
                        menuMealCard(meal, fitsBudget: remaining > 0 && meal.calories <= remaining)
                    }
                    .buttonStyle(.plain)
                }

                Text("AI estimates — double-check before logging.")
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .padding()
        }
    }

    private func menuBudgetBanner(remaining: Double) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .appFont(size: 14, weight: .bold)
                .foregroundColor(.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("All picks exceed your remaining \(Int(remaining)) cal")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text("These are the closest options on the menu — log mindfully or save room elsewhere.")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func menuMealCard(_ meal: FoodItem, fitsBudget: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 44, height: 44)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(meal.name)
                    .appFont(size: 16, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                HStack(spacing: 9) {
                    Text("\(Int(meal.calories)) cal").foregroundColor(.brandPrimary)
                    Text("P \(Int(meal.protein))g").foregroundColor(.accentProtein)
                    Text("C \(Int(meal.carbs))g").foregroundColor(.accentCarbs)
                    Text("F \(Int(meal.fats))g").foregroundColor(.accentFats)
                }
                .appFont(size: 12, weight: .semibold)

                if fitsBudget {
                    Text("Fits your budget")
                        .appFont(size: 10, weight: .bold)
                        .foregroundColor(.accentPositive)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentPositive.opacity(0.14), in: Capsule())
                }
            }

            Spacer(minLength: 6)

            Image(systemName: "plus.circle.fill")
                .appFont(size: 26)
                .foregroundColor(.brandPrimary)
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        
        let remainingCals = max(0, (goalSettings.calories ?? 2000) - (dailyLogService.currentDailyLog?.totalCalories() ?? 0))
        let remainingPro = max(0, goalSettings.protein - (dailyLogService.currentDailyLog?.totalMacros().protein ?? 0))
        remainingCaloriesSnapshot = remainingCals
        
        aiModel.recommendMenuMeals(from: image, remainingCalories: remainingCals, remainingProtein: remainingPro) { result in
            isProcessing = false
            switch result {
            case .success(let meals):
                if meals.isEmpty {
                    errorMessage = "We couldn't find any good matches on this menu."
                } else {
                    recommendedMeals = Array(meals.prefix(5))
                }
            case .failure(let error):
                errorMessage = "Failed to analyze menu: \(error.localizedDescription)"
            }
        }
    }
    
    private func logMeal(_ meal: FoodItem) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.addFoodToCurrentLog(for: userID, foodItem: meal, source: "MenuMatchmaker")
        dismiss()
    }
}
