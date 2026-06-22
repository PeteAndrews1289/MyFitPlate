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
    
    private let aiModel = MLImageModel()
    
    var body: some View {
        NavigationStack {
            VStack {
                if isProcessing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Analyzing menu & crunching macros...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !recommendedMeals.isEmpty {
                    List {
                        Section(header: Text("Top 3 Recommendations")) {
                            ForEach(recommendedMeals) { meal in
                                Button(action: { logMeal(meal) }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(meal.name)
                                                .font(.headline)
                                                .foregroundColor(.textPrimary)
                                            HStack(spacing: 12) {
                                                Text("\(Int(meal.calories)) kcal")
                                                Text("\(Int(meal.protein))g Protein")
                                            }
                                            .font(.subheadline)
                                            .foregroundColor(.brandPrimary)
                                            
                                            HStack(spacing: 12) {
                                                Text("\(Int(meal.carbs))g Carbs")
                                                Text("\(Int(meal.fats))g Fat")
                                            }
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.accentPositive)
                                            .font(.title2)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    VStack(spacing: 24) {
                        Image(systemName: "menucard")
                            .font(.system(size: 60))
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
            .navigationTitle("Menu Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        
        let remainingCals = max(0, (goalSettings.calories ?? 2000) - (dailyLogService.currentDailyLog?.totalCalories() ?? 0))
        let remainingPro = max(0, goalSettings.protein - (dailyLogService.currentDailyLog?.totalMacros().protein ?? 0))
        
        aiModel.recommendMenuMeals(from: image, remainingCalories: remainingCals, remainingProtein: remainingPro) { result in
            isProcessing = false
            switch result {
            case .success(let meals):
                if meals.isEmpty {
                    errorMessage = "We couldn't find any good matches on this menu."
                } else {
                    recommendedMeals = Array(meals.prefix(3))
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
