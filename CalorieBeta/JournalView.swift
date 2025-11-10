import SwiftUI
import FirebaseAuth

struct JournalView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    
    @State private var entryText: String = ""
    @State private var selectedCategory: String = "Recovery"
    let categories = ["Recovery", "Mindfulness", "Flexibility", "Other"]

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("How are you feeling?")) {
                        TextEditor(text: $entryText)
                            .frame(height: 150)
                    }
                    
                    Section {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) {
                                Text($0)
                            }
                        }
                    }
                }
                
                Button(action: saveEntry) {
                    Label("Save to Journal", systemImage: "book.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(entryText.isEmpty)
                .padding()
            }
            .navigationTitle("New Journal Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func saveEntry() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let newEntry = JournalEntry(
            date: Date(),
            text: entryText,
            category: selectedCategory
        )
        Task {
            await dailyLogService.addJournalEntry(for: userID, entry: newEntry)
        }
        dismiss()
    }
}
