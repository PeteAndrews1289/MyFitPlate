import SwiftUI
import FirebaseAuth

struct MealPlanSurveyView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @Environment(\.dismiss) var dismiss

    @State private var selectedProteins: Set<String> = ["Chicken"]
    @State private var selectedCarbs: Set<String> = ["Rice"]
    @State private var selectedVeggies: Set<String> = ["Broccoli", "Bell Peppers", "Onions"]
    @State private var selectedSnacks: Set<String> = ["Yogurt", "Fruit"]
    @State private var selectedCuisines: Set<String> = ["Any"]

    @State private var customProtein: String = ""
    @State private var customCarb: String = ""
    @State private var customVeggies: String = ""
    @State private var customSnack: String = ""

    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    @State private var currentStep = 0
    let totalSteps = 5

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
                        .padding(.horizontal)
                        .padding(.top)
                        .tint(Color.brandPrimary)

                    TabView(selection: $currentStep) {
                        stepView(title: "Choose Your Proteins", iconName: "fish.fill") {
                            SurveySelectionView(
                                title: "Proteins",
                                items: ProteinChoice.allCases.map { $0.rawValue },
                                selectedItems: $selectedProteins,
                                customItem: $customProtein
                            )
                        }.tag(0)

                        stepView(title: "Select Your Carbs", iconName: "bag.fill") {
                            SurveySelectionView(
                                title: "Carbohydrates",
                                items: CarbChoice.allCases.map { $0.rawValue },
                                selectedItems: $selectedCarbs,
                                customItem: $customCarb
                            )
                        }.tag(1)

                        stepView(title: "Pick Your Vegetables", iconName: "carrot.fill") {
                            SurveySelectionView(
                                title: "Vegetables",
                                items: VeggieChoice.allCases.map { $0.rawValue },
                                selectedItems: $selectedVeggies,
                                customItem: $customVeggies
                            )
                        }.tag(2)

                        stepView(title: "Choose Your Snacks", iconName: "fork.knife") {
                            SurveySelectionView(
                                title: "Snacks",
                                items: SnackChoice.allCases.map { $0.rawValue },
                                selectedItems: $selectedSnacks,
                                customItem: $customSnack
                            )
                        }.tag(3)

                        stepView(title: "Cuisine Influence", iconName: "globe.americas.fill") {
                            CuisineSelectionView(selectedCuisines: $selectedCuisines)
                        }.tag(4)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentStep)

                    HStack {
                        if currentStep > 0 {
                            Button("Back") { withAnimation { currentStep -= 1 } }
                                .buttonStyle(SecondaryButtonStyle())
                        }

                        if currentStep == totalSteps - 1 {
                            Button(action: generateAndSavePlan) {
                                Label("Generate 7-Day Meal Plan", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(isLoading)
                        } else {
                            Button("Next") { withAnimation { currentStep += 1 } }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .padding()
                }
                .background(Color.backgroundPrimary.ignoresSafeArea())
                .navigationTitle("Meal Plan Generator")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .alert("Status", isPresented: $showAlert) {
                    Button("OK") { if !alertMessage.contains("Error") { dismiss() } }
                } message: { Text(alertMessage) }

                if isLoading {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5)
                        Text("Generating Your 7-Day Plan...\nThis may take a moment.").multilineTextAlignment(.center)
                    }
                    .padding(30)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
            }
        }
    }
    
    @ViewBuilder
    private func stepView<Content: View>(title: String, iconName: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: iconName)
                    .font(.system(size: 40))
                    .foregroundColor(.brandPrimary)
                    .padding(.bottom, 5)
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                content()
                
                Spacer()
            }
            .padding()
        }
    }

    private func generateAndSavePlan() {
        isLoading = true
        alertMessage = ""

        var foodList = Array(selectedProteins)
        if !customProtein.isEmpty { foodList.append(customProtein) }
        foodList.append(contentsOf: Array(selectedCarbs))
        if !customCarb.isEmpty { foodList.append(customCarb) }
        foodList.append(contentsOf: Array(selectedVeggies))
        if !customVeggies.isEmpty { foodList.append(customVeggies) }

        let cuisineList = Array(selectedCuisines)
        let snackList = Array(selectedSnacks) + (customSnack.isEmpty ? [] : [customSnack])

        Task {
            guard let userID = Auth.auth().currentUser?.uid else {
                handleError("You must be logged in.")
                return
            }

            let success = await mealPlannerService.generateAndSaveFullWeekPlan(
                goals: goalSettings,
                preferredFoods: foodList,
                preferredCuisines: cuisineList,
                preferredSnacks: snackList,
                userID: userID
            )

            isLoading = false

            if success {
                alertMessage = "Your 7-day meal plan has been generated!"
            } else {
                alertMessage = "There was an error generating the plan. The AI may have returned an invalid response. Please try again."
            }
            showAlert = true
        }
    }

    private func handleError(_ message: String) {
        isLoading = false
        alertMessage = message
        showAlert = true
    }
}

private struct SurveySelectionView: View {
    let title: String
    let items: [String]
    @Binding var selectedItems: Set<String>
    @Binding var customItem: String
    
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items, id: \.self) { item in
                    Button(action: {
                        if selectedItems.contains(item) {
                            selectedItems.remove(item)
                        } else {
                            selectedItems.insert(item)
                        }
                    }) {
                        Text(item)
                            .appFont(size: 16, weight: .medium)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(selectedItems.contains(item) ? Color.brandPrimary.opacity(0.2) : Color.backgroundSecondary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedItems.contains(item) ? Color.brandPrimary : Color.clear, lineWidth: 2)
                            )
                            .foregroundColor(.textPrimary)
                    }
                }
            }
            TextField("Other (e.g., Lamb)", text: $customItem)
                .textFieldStyle(AppTextFieldStyle(iconName: nil))
                .padding(.top)
        }
    }
}

private struct CuisineSelectionView: View {
    @Binding var selectedCuisines: Set<String>
    let allCuisines = ["Any", "Italian", "Mexican", "Asian", "Mediterranean", "American"]
    
    private func iconForCuisine(_ cuisine: String) -> String {
        switch cuisine {
        case "Italian": return "wineglass.fill"
        case "Mexican": return "flame.fill"
        case "Asian": return "globe.asia.australia.fill"
        case "Mediterranean": return "leaf.fill"
        case "American": return "flag.fill"
        default: return "globe.americas.fill"
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(allCuisines, id: \.self) { cuisine in
                    Button(action: {
                        toggleCuisineSelection(cuisine)
                    }) {
                        VStack {
                            Image(systemName: iconForCuisine(cuisine))
                                .font(.largeTitle)
                                .frame(width: 120, height: 100)
                                .background(Color.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    ZStack {
                                        if selectedCuisines.contains(cuisine) {
                                            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.4))
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.largeTitle)
                                                .foregroundColor(.white)
                                        }
                                    }
                                )
                            Text(cuisine)
                                .appFont(size: 16, weight: .semibold)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func toggleCuisineSelection(_ cuisine: String) {
        if cuisine == "Any" {
            if selectedCuisines.contains("Any") {
                selectedCuisines = []
            } else {
                selectedCuisines = ["Any"]
            }
        } else {
            selectedCuisines.remove("Any")
            if selectedCuisines.contains(cuisine) {
                selectedCuisines.remove(cuisine)
            } else {
                selectedCuisines.insert(cuisine)
            }
        }
    }
}

fileprivate enum ProteinChoice: String, CaseIterable, Identifiable { case chicken = "Chicken", beef = "Beef", fish = "Fish", tofu = "Tofu", eggs = "Eggs", pork = "Pork"; var id: Self { self } }
fileprivate enum CarbChoice: String, CaseIterable, Identifiable { case rice = "Rice", quinoa = "Quinoa", potatoes = "Potatoes", pasta = "Pasta", bread = "Bread", oats = "Oats"; var id: Self { self } }
fileprivate enum VeggieChoice: String, CaseIterable, Identifiable { case broccoli = "Broccoli", spinach = "Spinach", bellPeppers = "Bell Peppers", onions = "Onions", carrots = "Carrots", zucchini = "Zucchini"; var id: Self { self } }
fileprivate enum SnackChoice: String, CaseIterable, Identifiable { case yogurt = "Yogurt", nuts = "Nuts", fruit = "Fruit", proteinBar = "Protein Bar"; var id: Self { self } }
