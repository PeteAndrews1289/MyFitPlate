import SwiftUI

struct SuggestionPreferencesView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedProteins: Set<String>
    @State private var selectedCuisines: Set<String>

    let allProteins = ["Chicken", "Beef", "Fish", "Tofu", "Eggs", "Pork", "Lamb"]
    let allCuisines = ["Any", "Italian", "Mexican", "Asian", "Mediterranean", "American"]

    init(goalSettings: GoalSettings) {
        _selectedProteins = State(initialValue: Set(goalSettings.suggestionProteins))
        _selectedCuisines = State(initialValue: Set(goalSettings.suggestionCuisines))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Preferred Proteins")) {
                    ForEach(allProteins, id: \.self) { protein in
                        multiSelectRow(item: protein, selection: $selectedProteins)
                    }
                }
                
                Section(header: Text("Preferred Cuisines")) {
                    ForEach(allCuisines, id: \.self) { cuisine in
                        multiSelectRow(item: cuisine, selection: $selectedCuisines)
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

    private func multiSelectRow(item: String, selection: Binding<Set<String>>) -> some View {
        Button(action: {
            if selection.wrappedValue.contains(item) {
                selection.wrappedValue.remove(item)
            } else {
                if item == "Any" {
                    selection.wrappedValue = ["Any"]
                } else {
                    selection.wrappedValue.remove("Any")
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
        goalSettings.suggestionCuisines = Array(selectedCuisines)
        if let userID = Auth.auth().currentUser?.uid {
            goalSettings.saveUserGoals(userID: userID)
        }
        dismiss()
    }
}