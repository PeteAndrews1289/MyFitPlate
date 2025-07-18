import SwiftUI
import FirebaseAuth

struct SuggestionPreferencesView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedProteins: Set<String>
    @State private var selectedCarbs: Set<String>
    @State private var selectedVeggies: Set<String>
    @State private var selectedCuisines: Set<String>

    let allProteins = ["Chicken", "Beef", "Fish", "Tofu", "Eggs", "Pork", "Lamb"]
    let allCarbs = ["Rice", "Quinoa", "Potatoes", "Pasta", "Bread", "Oats"]
    let allVeggies = ["Broccoli", "Spinach", "Bell Peppers", "Onions", "Carrots", "Zucchini", "Asparagus"]
    let allCuisines = ["Any", "Italian", "Mexican", "Asian", "Mediterranean", "American"]

    init(goalSettings: GoalSettings) {
        _selectedProteins = State(initialValue: Set(goalSettings.suggestionProteins))
        _selectedCarbs = State(initialValue: Set(goalSettings.suggestionCarbs))
        _selectedVeggies = State(initialValue: Set(goalSettings.suggestionVeggies))
        _selectedCuisines = State(initialValue: Set(goalSettings.suggestionCuisines))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Preferred Proteins")) {
                    ForEach(allProteins, id: \.self) { item in
                        multiSelectRow(item: item, selection: $selectedProteins)
                    }
                }

                Section(header: Text("Preferred Carbs")) {
                    ForEach(allCarbs, id: \.self) { item in
                        multiSelectRow(item: item, selection: $selectedCarbs)
                    }
                }
                
                Section(header: Text("Preferred Veggies")) {
                    ForEach(allVeggies, id: \.self) { item in
                        multiSelectRow(item: item, selection: $selectedVeggies)
                    }
                }
                
                Section(header: Text("Preferred Cuisines")) {
                    ForEach(allCuisines, id: \.self) { cuisine in
                        multiSelectRow(item: cuisine, selection: $selectedCuisines, isExclusive: true)
                    }
                }
            }
            .navigationTitle("Suggestion Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                }
            }
        }
    }

    private func multiSelectRow(item: String, selection: Binding<Set<String>>, isExclusive: Bool = false) -> some View {
        Button(action: {
            if isExclusive {
                if item == "Any" {
                    selection.wrappedValue = ["Any"]
                } else {
                    selection.wrappedValue.remove("Any")
                    if selection.wrappedValue.contains(item) {
                        selection.wrappedValue.remove(item)
                    } else {
                        selection.wrappedValue.insert(item)
                    }
                }
            } else {
                if selection.wrappedValue.contains(item) {
                    selection.wrappedValue.remove(item)
                } else {
                    selection.wrappedValue.insert(item)
                }
            }
        }) {
            HStack {
                Text(item)
                Spacer()
                if selection.wrappedValue.contains(item) {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundColor(.primary)
    }

    private func saveAndDismiss() {
        goalSettings.suggestionProteins = Array(selectedProteins)
        goalSettings.suggestionCarbs = Array(selectedCarbs)
        goalSettings.suggestionVeggies = Array(selectedVeggies)
        goalSettings.suggestionCuisines = Array(selectedCuisines)
        if let userID = Auth.auth().currentUser?.uid {
            goalSettings.saveUserGoals(userID: userID)
        }
        dismiss()
    }
}
