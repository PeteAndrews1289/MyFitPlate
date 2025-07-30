import SwiftUI
import FirebaseAuth

struct MealPlanSurveyView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @Environment(\.dismiss) var dismiss

 
    @State private var selectedProteins: Set<ProteinChoice> = [.chicken]
    @State private var selectedCarbs: Set<CarbChoice> = [.rice]
    @State private var selectedVeggies: Set<VeggieChoice> = [.broccoli, .bellPeppers, .onions]
    @State private var selectedSnacks: Set<SnackChoice> = [.yogurt, .fruit]
    
    @State private var selectedCuisines: Set<CuisineChoice> = []

    @State private var customProtein: String = ""
    @State private var customCarb: String = ""
    @State private var customVeggies: String = ""
    @State private var customSnack: String = ""
    
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    
    enum ProteinChoice: String, CaseIterable, Identifiable { case chicken, beef, fish, tofu, eggs; var id: Self { self } }
    enum CarbChoice: String, CaseIterable, Identifiable { case rice, quinoa, sweetPotato = "Sweet Potato", pasta, bread; var id: Self { self } }
    enum VeggieChoice: String, CaseIterable, Identifiable { case broccoli, spinach, bellPeppers = "Bell Peppers", onions, carrots, zucchini; var id: Self { self } }
    enum SnackChoice: String, CaseIterable, Identifiable { case yogurt, nuts, fruit, proteinBar = "Protein Bar"; var id: Self { self } }
  
    enum CuisineChoice: String, CaseIterable, Identifiable {
        case any = "Any / No Preference"
        case italian = "Italian"
        case mexican = "Mexican"
        case asian = "Asian"
        case mediterranean = "Mediterranean"
        case american = "American"
        var id: Self { self }
    }


    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    Section(header: Text("Step 1: Choose Your Protein(s)")) {
                        List { ForEach(ProteinChoice.allCases) { multiSelectRow(item: $0, selection: $selectedProteins) } }
                        TextField("Custom protein (e.g., Lamb)", text: $customProtein)
                    }
                    Section(header: Text("Step 2: Choose Your Carb Source(s)")) {
                        List { ForEach(CarbChoice.allCases) { multiSelectRow(item: $0, selection: $selectedCarbs) } }
                        TextField("Custom carb (e.g., Sourdough)", text: $customCarb)
                    }
                    Section(header: Text("Step 3: Pick Your Vegetables")) {
                        List { ForEach(VeggieChoice.allCases) { multiSelectRow(item: $0, selection: $selectedVeggies) } }
                        TextField("Custom veggies (e.g., Asparagus)", text: $customVeggies)
                    }
                    
                    Section(header: Text("Step 4: Choose Your Snacks (Optional)")) {
                        List { ForEach(SnackChoice.allCases) { multiSelectRow(item: $0, selection: $selectedSnacks) } }
                        TextField("Custom snack (e.g., Rice Cakes)", text: $customSnack)
                    }
                    
                    Section(header: Text("Step 5: Add Cuisine Influence (Optional)")) {
                        List {
                            ForEach(CuisineChoice.allCases) { cuisine in
                                Button(action: {
                                    toggleCuisineSelection(cuisine)
                                }) {
                                    HStack {
                                        Text(cuisine.rawValue.capitalized)
                                        Spacer()
                                        if selectedCuisines.contains(cuisine) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.brandPrimary)
                                        }
                                    }.contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }

                    Section {
                        Button {
                            generateAndSavePlan()
                        } label: {
                            Label("Generate 7-Day Meal Plan", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selectedProteins.isEmpty && customProtein.isEmpty || isLoading)
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical)
                    }
                }
                
                if isLoading {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Generating 7-Day Plan...")
                            .multilineTextAlignment(.center)
                        Text("This may take a moment.")
                            .appFont(size: 12)
                    }
                    .padding(30)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
            }
            .navigationTitle("Meal Plan Generator")
            .navigationBarItems(leading: Button("Cancel") { dismiss() })
            .alert("Status", isPresented: $showAlert) { Button("OK") { if !alertMessage.contains("Error") { dismiss() } } } message: { Text(alertMessage) }
        }
    }
    
    private func toggleCuisineSelection(_ cuisine: CuisineChoice) {
        if cuisine == .any {
            if selectedCuisines.contains(.any) {
                selectedCuisines = []
            } else {
                selectedCuisines = [.any]
            }
        } else {
            selectedCuisines.remove(.any)
            if selectedCuisines.contains(cuisine) {
                selectedCuisines.remove(cuisine)
            } else {
                selectedCuisines.insert(cuisine)
            }
        }
    }

    @ViewBuilder
    private func multiSelectRow<T: RawRepresentable & Hashable & Identifiable>(item: T, selection: Binding<Set<T>>) -> some View where T.RawValue == String {
        Button(action: {
            if selection.wrappedValue.contains(item) { selection.wrappedValue.remove(item) } else { selection.wrappedValue.insert(item) }
        }) {
            HStack {
                Text(item.rawValue.capitalized)
                Spacer()
                if selection.wrappedValue.contains(item) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.brandPrimary)
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func generateAndSavePlan() {
        isLoading = true
        alertMessage = ""
        
        var foodList = selectedProteins.map { $0.rawValue }
        if !customProtein.isEmpty { foodList.append(customProtein) }
        foodList.append(contentsOf: selectedCarbs.map { $0.rawValue })
        if !customCarb.isEmpty { foodList.append(customCarb) }
        foodList.append(contentsOf: selectedVeggies.map { $0.rawValue })
        if !customVeggies.isEmpty { foodList.append(customVeggies) }
        
        let cuisineList = selectedCuisines.map { $0.rawValue }
        let snackList = selectedSnacks.map { $0.rawValue } + (customSnack.isEmpty ? [] : [customSnack])


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
