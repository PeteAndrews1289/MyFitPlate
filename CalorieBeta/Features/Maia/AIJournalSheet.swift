import SwiftUI

struct AIJournalSheet: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    @State private var showingAddJournalView = false

    private func deleteJournalEntry(at offsets: IndexSet) {
        guard let userID = DIContainer.shared.authService.currentUserID,
                let allEntries = dailyLogService.currentDailyLog?.journalEntries else { return }
        
        let entriesToDelete = offsets.map { allEntries[$0] }
        
        for entry in entriesToDelete {
            dailyLogService.journalEntryStore.deleteJournalEntry(for: userID, entry: entry)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let entries = dailyLogService.currentDailyLog?.journalEntries, !entries.isEmpty {
                    List {
                        ForEach(entries) { entry in
                            HStack(spacing: 12) {
                                Text(JournalEmojiMapper.getEmoji(for: entry.category))
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(Color.backgroundSecondary)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.text)
                                        .appFont(size: 16, weight: .medium)
                                        .foregroundColor(.textPrimary)
                                        .lineLimit(2)
                                    
                                    Text(entry.category)
                                        .appFont(size: 13)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteJournalEntry)
                    }
                    .listStyle(.insetGrouped)
                    
                } else {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "book.closed")
                            .appFont(size: 50)
                            .foregroundColor(.secondary)
                            .opacity(0.5)
                        
                        Text("No journal entries for today.")
                            .appFont(size: 16, weight: .medium)
                            .foregroundColor(.secondary)
                        
                        Button("Write First Entry") {
                            showingAddJournalView = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 40)
                        Spacer()
                    }
                }
            }
            .navigationTitle("AI Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddJournalView = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddJournalView) {
                JournalView()
            }
        }
    }
}

struct JournalView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    
    @State private var entryText: String = ""
    @State private var selectedCategory: String = "Recovery"
    let categories = ["Recovery", "Mindfulness", "Flexibility", "Other"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Category")) {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: Text("How are you feeling?")) {
                    TextEditor(text: $entryText)
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEntry() }
                        .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveEntry() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let newEntry = JournalEntry(
            date: Date(),
            text: entryText,
            category: selectedCategory
        )
        Task {
            await dailyLogService.journalEntryStore.addJournalEntry(for: userID, entry: newEntry)
        }
        dismiss()
    }
}
