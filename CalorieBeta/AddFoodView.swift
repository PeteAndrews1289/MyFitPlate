import SwiftUI

struct AddFoodView: View {
    @Binding var isPresented: Bool
    var foodItem: FoodItem?
    var onFoodLogged: (FoodItem, String) -> Void

    @State private var foodName = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fats = ""
    @State private var selectedMeal = "Breakfast"
    let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snacks"]
    
    @State private var saturatedFat = ""
    @State private var polyunsaturatedFat = ""
    @State private var monounsaturatedFat = ""
    @State private var fiber = ""
    @State private var calcium = ""
    @State private var iron = ""
    @State private var potassium = ""
    @State private var sodium = ""
    @State private var vitaminA = ""
    @State private var vitaminC = ""
    @State private var vitaminD = ""
    @State private var vitaminB12 = ""
    @State private var folate = ""
    @State private var magnesium = ""
    @State private var phosphorus = ""
    @State private var zinc = ""
    @State private var copper = ""
    @State private var manganese = ""
    @State private var selenium = ""
    @State private var vitaminB1 = ""
    @State private var vitaminB2 = ""
    @State private var vitaminB3 = ""
    @State private var vitaminB5 = ""
    @State private var vitaminB6 = ""
    @State private var vitaminE = ""
    @State private var vitaminK = ""
    
    @State private var showingImagePicker = false
    @State private var isProcessingLabel = false
    @State private var scanError: (Bool, String) = (false, "")
    
    private let imageModel = MLImageModel()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            NavigationView {
                VStack {
                    Form {
                        Section {
                            Picker("Log to Meal", selection: $selectedMeal) {
                                ForEach(mealTypes, id: \.self) {
                                    Text($0)
                                }
                            }
                        }
                        
                        Section(header: Text("Nutritional Information"), footer: Text("Tap the camera icon to scan a nutrition label automatically.")) {
                            HStack {
                                TextField("Food Name", text: $foodName)
                                Button {
                                    showingImagePicker = true
                                } label: {
                                    Image(systemName: "camera.fill")
                                        .font(.title2)
                                        .foregroundColor(.brandPrimary)
                                }
                            }
                            
                            TextField("Calories (kcal)", text: $calories)
                                .keyboardType(.decimalPad)
                            TextField("Protein (g)", text: $protein)
                                .keyboardType(.decimalPad)
                            TextField("Carbs (g)", text: $carbs)
                                .keyboardType(.decimalPad)
                            TextField("Fats (g)", text: $fats)
                                .keyboardType(.decimalPad)
                            
                            DisclosureGroup("Add Micronutrients (Optional)") {
                                Group {
                                    TextField("Saturated Fat (g)", text: $saturatedFat).keyboardType(.decimalPad)
                                    TextField("Polyunsaturated Fat (g)", text: $polyunsaturatedFat).keyboardType(.decimalPad)
                                    TextField("Monounsaturated Fat (g)", text: $monounsaturatedFat).keyboardType(.decimalPad)
                                    TextField("Fiber (g)", text: $fiber).keyboardType(.decimalPad)
                                    TextField("Calcium (mg)", text: $calcium).keyboardType(.decimalPad)
                                    TextField("Iron (mg)", text: $iron).keyboardType(.decimalPad)
                                    TextField("Potassium (mg)", text: $potassium).keyboardType(.decimalPad)
                                    TextField("Sodium (mg)", text: $sodium).keyboardType(.decimalPad)
                                    TextField("Vitamin A (mcg)", text: $vitaminA).keyboardType(.decimalPad)
                                    TextField("Vitamin C (mg)", text: $vitaminC).keyboardType(.decimalPad)
                                }
                                Group {
                                    TextField("Vitamin D (mcg)", text: $vitaminD).keyboardType(.decimalPad)
                                    TextField("Vitamin B12 (mcg)", text: $vitaminB12).keyboardType(.decimalPad)
                                    TextField("Folate (mcg)", text: $folate).keyboardType(.decimalPad)
                                    TextField("Magnesium (mg)", text: $magnesium).keyboardType(.decimalPad)
                                    TextField("Phosphorus (mg)", text: $phosphorus).keyboardType(.decimalPad)
                                    TextField("Zinc (mg)", text: $zinc).keyboardType(.decimalPad)
                                    TextField("Copper (mcg)", text: $copper).keyboardType(.decimalPad)
                                    TextField("Manganese (mg)", text: $manganese).keyboardType(.decimalPad)
                                    TextField("Selenium (mcg)", text: $selenium).keyboardType(.decimalPad)
                                    TextField("Vitamin B1 (mg)", text: $vitaminB1).keyboardType(.decimalPad)
                                }
                                Group {
                                    TextField("Vitamin B2 (mg)", text: $vitaminB2).keyboardType(.decimalPad)
                                    TextField("Vitamin B3 (mg)", text: $vitaminB3).keyboardType(.decimalPad)
                                    TextField("Vitamin B5 (mg)", text: $vitaminB5).keyboardType(.decimalPad)
                                    TextField("Vitamin B6 (mg)", text: $vitaminB6).keyboardType(.decimalPad)
                                    TextField("Vitamin E (mg)", text: $vitaminE).keyboardType(.decimalPad)
                                    TextField("Vitamin K (mcg)", text: $vitaminK).keyboardType(.decimalPad)
                                }
                            }
                        }
                    }
                    
                    Button(action: logFood) {
                        Text("Log Food")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding()
                    .disabled(foodName.isEmpty || calories.isEmpty)
                }
                .navigationTitle(foodItem == nil ? "Add Food Manually" : "Add to Log")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .onAppear(perform: populateFromFoodItem)
                .sheet(isPresented: $showingImagePicker) {
                    ImagePicker(sourceType: .camera) { image in
                        self.isProcessingLabel = true
                        imageModel.parseNutritionLabel(from: image) { result in
                            self.isProcessingLabel = false
                            switch result {
                            case .success(let nutrition):
                                self.handleScannedNutrition(nutrition)
                            case .failure(let error):
                                self.scanError = (true, "Could not read the nutrition label. Please try again. Error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                .alert("Scan Error", isPresented: $scanError.0) {
                    Button("OK") { }
                } message: {
                    Text(scanError.1)
                }
            }
            
            if isProcessingLabel {
                Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                ProgressView("Reading Label...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
                    .scaleEffect(1.5)
            }
        }
    }

    private func populateFromFoodItem() {
        guard let item = foodItem else { return }
        foodName = item.name
        calories = String(format: "%.0f", item.calories)
        protein = String(format: "%.1f", item.protein)
        carbs = String(format: "%.1f", item.carbs)
        fats = String(format: "%.1f", item.fats)
        saturatedFat = String(format: "%.1f", item.saturatedFat ?? 0)
        polyunsaturatedFat = String(format: "%.1f", item.polyunsaturatedFat ?? 0)
        monounsaturatedFat = String(format: "%.1f", item.monounsaturatedFat ?? 0)
        fiber = String(format: "%.1f", item.fiber ?? 0)
        calcium = String(format: "%.0f", item.calcium ?? 0)
        iron = String(format: "%.1f", item.iron ?? 0)
        potassium = String(format: "%.0f", item.potassium ?? 0)
        sodium = String(format: "%.0f", item.sodium ?? 0)
        vitaminA = String(format: "%.0f", item.vitaminA ?? 0)
        vitaminC = String(format: "%.0f", item.vitaminC ?? 0)
        vitaminD = String(format: "%.0f", item.vitaminD ?? 0)
        vitaminB12 = String(format: "%.1f", item.vitaminB12 ?? 0)
        folate = String(format: "%.0f", item.folate ?? 0)
        magnesium = String(format: "%.0f", item.magnesium ?? 0)
        phosphorus = String(format: "%.0f", item.phosphorus ?? 0)
        zinc = String(format: "%.1f", item.zinc ?? 0)
        copper = String(format: "%.0f", item.copper ?? 0)
        manganese = String(format: "%.1f", item.manganese ?? 0)
        selenium = String(format: "%.0f", item.selenium ?? 0)
        vitaminB1 = String(format: "%.1f", item.vitaminB1 ?? 0)
        vitaminB2 = String(format: "%.1f", item.vitaminB2 ?? 0)
        vitaminB3 = String(format: "%.1f", item.vitaminB3 ?? 0)
        vitaminB5 = String(format: "%.1f", item.vitaminB5 ?? 0)
        vitaminB6 = String(format: "%.1f", item.vitaminB6 ?? 0)
        vitaminE = String(format: "%.1f", item.vitaminE ?? 0)
        vitaminK = String(format: "%.0f", item.vitaminK ?? 0)
    }

    private func handleScannedNutrition(_ nutrition: NutritionLabelData) {
        self.foodName = nutrition.foodName
        self.calories = String(format: "%.0f", nutrition.calories)
        self.protein = String(format: "%.1f", nutrition.protein)
        self.carbs = String(format: "%.1f", nutrition.carbs)
        self.fats = String(format: "%.1f", nutrition.fats)
        self.saturatedFat = String(format: "%.1f", nutrition.saturatedFat ?? 0)
        self.polyunsaturatedFat = String(format: "%.1f", nutrition.polyunsaturatedFat ?? 0)
        self.monounsaturatedFat = String(format: "%.1f", nutrition.monounsaturatedFat ?? 0)
        self.fiber = String(format: "%.1f", nutrition.fiber ?? 0)
        self.calcium = String(format: "%.0f", nutrition.calcium ?? 0)
        self.iron = String(format: "%.1f", nutrition.iron ?? 0)
        self.potassium = String(format: "%.0f", nutrition.potassium ?? 0)
        self.sodium = String(format: "%.0f", nutrition.sodium ?? 0)
        self.vitaminA = String(format: "%.0f", nutrition.vitaminA ?? 0)
        self.vitaminC = String(format: "%.0f", nutrition.vitaminC ?? 0)
        self.vitaminD = String(format: "%.0f", nutrition.vitaminD ?? 0)
        self.vitaminB12 = String(format: "%.1f", nutrition.vitaminB12 ?? 0)
        self.folate = String(format: "%.0f", nutrition.folate ?? 0)
        self.magnesium = String(format: "%.0f", nutrition.magnesium ?? 0)
        self.phosphorus = String(format: "%.0f", nutrition.phosphorus ?? 0)
        self.zinc = String(format: "%.1f", nutrition.zinc ?? 0)
        self.copper = String(format: "%.0f", nutrition.copper ?? 0)
        self.manganese = String(format: "%.1f", nutrition.manganese ?? 0)
        self.selenium = String(format: "%.0f", nutrition.selenium ?? 0)
        self.vitaminB1 = String(format: "%.1f", nutrition.vitaminB1 ?? 0)
        self.vitaminB2 = String(format: "%.1f", nutrition.vitaminB2 ?? 0)
        self.vitaminB3 = String(format: "%.1f", nutrition.vitaminB3 ?? 0)
        self.vitaminB5 = String(format: "%.1f", nutrition.vitaminB5 ?? 0)
        self.vitaminB6 = String(format: "%.1f", nutrition.vitaminB6 ?? 0)
        self.vitaminE = String(format: "%.1f", nutrition.vitaminE ?? 0)
        self.vitaminK = String(format: "%.0f", nutrition.vitaminK ?? 0)
    }

    private func logFood() {
        guard !foodName.isEmpty, let caloriesValue = Double(calories) else {
            return
        }

        let newFood = FoodItem(
            id: foodItem?.id ?? UUID().uuidString,
            name: foodName,
            calories: caloriesValue,
            protein: Double(protein) ?? 0.0,
            carbs: Double(carbs) ?? 0.0,
            fats: Double(fats) ?? 0.0,
            saturatedFat: Double(saturatedFat) ?? 0.0,
            polyunsaturatedFat: Double(polyunsaturatedFat) ?? 0.0,
            monounsaturatedFat: Double(monounsaturatedFat) ?? 0.0,
            fiber: Double(fiber) ?? 0.0,
            servingSize: "1 serving",
            servingWeight: 0.0,
            calcium: Double(calcium) ?? 0.0,
            iron: Double(iron) ?? 0.0,
            potassium: Double(potassium) ?? 0.0,
            sodium: Double(sodium) ?? 0.0,
            vitaminA: Double(vitaminA) ?? 0.0,
            vitaminC: Double(vitaminC) ?? 0.0,
            vitaminD: Double(vitaminD) ?? 0.0,
            vitaminB12: Double(vitaminB12) ?? 0.0,
            folate: Double(folate) ?? 0.0,
            magnesium: Double(magnesium) ?? 0.0,
            phosphorus: Double(phosphorus) ?? 0.0,
            zinc: Double(zinc) ?? 0.0,
            copper: Double(copper) ?? 0.0,
            manganese: Double(manganese) ?? 0.0,
            selenium: Double(selenium) ?? 0.0,
            vitaminB1: Double(vitaminB1) ?? 0.0,
            vitaminB2: Double(vitaminB2) ?? 0.0,
            vitaminB3: Double(vitaminB3) ?? 0.0,
            vitaminB5: Double(vitaminB5) ?? 0.0,
            vitaminB6: Double(vitaminB6) ?? 0.0,
            vitaminE: Double(vitaminE) ?? 0.0,
            vitaminK: Double(vitaminK) ?? 0.0
        )

        onFoodLogged(newFood, selectedMeal)
        dismiss()
    }
}
