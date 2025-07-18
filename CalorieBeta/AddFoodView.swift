import SwiftUI

struct AddFoodView: View {
    var onFoodLogged: (FoodItem) -> Void

    @State private var foodName = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fats = ""
    
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
                        }
                    }
                    
                    Button(action: logFood) {
                        Text("Log Food")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding()
                    .disabled(foodName.isEmpty || calories.isEmpty)
                }
                .navigationTitle("Add Food Manually")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .sheet(isPresented: $showingImagePicker) {
                    ImagePicker(sourceType: .camera) { image in
                        self.isProcessingLabel = true
                        imageModel.parseNutritionLabel(from: image) { result in
                            self.isProcessingLabel = false
                            switch result {
                            case .success(let nutrition):
                                // Populate the view's state with the results
                                self.foodName = nutrition.foodName
                                self.calories = String(format: "%.0f", nutrition.calories)
                                self.protein = String(format: "%.1f", nutrition.protein)
                                self.carbs = String(format: "%.1f", nutrition.carbs)
                                self.fats = String(format: "%.1f", nutrition.fats)
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

    private func logFood() {
        guard !foodName.isEmpty, let caloriesValue = Double(calories) else {
            return
        }

        let proteinValue = Double(protein) ?? 0.0
        let carbsValue = Double(carbs) ?? 0.0
        let fatsValue = Double(fats) ?? 0.0

        let newFood = FoodItem(
            id: UUID().uuidString,
            name: foodName,
            calories: caloriesValue,
            protein: proteinValue,
            carbs: carbsValue,
            fats: fatsValue,
            servingSize: "1 serving",
            servingWeight: 0.0
        )

        onFoodLogged(newFood)
        dismiss()
    }
}
