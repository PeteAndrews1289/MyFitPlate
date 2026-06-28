import Foundation
import FirebaseAnalytics

class JournalEntryStore {
    private weak var dailyLogService: DailyLogService?

    init(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }

    func addJournalEntry(for userID: String, entry: JournalEntry) async {
        guard let service = dailyLogService else { return }
        let dateToLog = service.activelyViewedDate
        let dateString = service.dateFormatter.string(from: dateToLog)

        do {
            if service.currentDailyLog?.date == dateToLog {
                await MainActor.run {
                    if service.currentDailyLog?.journalEntries == nil {
                        service.currentDailyLog?.journalEntries = []
                    }
                    service.currentDailyLog?.journalEntries?.append(entry)
                }
            }

            let logToSave = service.currentDailyLog ?? DailyLog(id: dateString, date: dateToLog, meals: [], journalEntries: [entry])
            try await DIContainer.shared.nutritionRepository.saveDailyLog(userID: userID, log: logToSave)

            Analytics.logEvent("journal_entry_added", parameters: [
                "category": entry.category
            ])

            await MainActor.run {
                service.bannerService?.showBanner(title: "Success", message: "Journal entry saved!")
            }

        } catch {
            AppLog.data.error("Failed to update journal entries: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                service.bannerService?.showBanner(title: "Error", message: "Failed to save journal entry.", iconName: "xmark.circle.fill", iconColor: .red)
            }
        }
    }

    func deleteJournalEntry(for userID: String, entry: JournalEntry) {
        guard let service = dailyLogService else { return }
        let dateToLog = service.activelyViewedDate

        if service.currentDailyLog?.date == dateToLog,
           let index = service.currentDailyLog?.journalEntries?.firstIndex(where: { $0.id == entry.id }) {
            DispatchQueue.main.async {
                service.currentDailyLog?.journalEntries?.remove(at: index)
            }
        }

        Task {
            do {
                if let log = service.currentDailyLog {
                    try await DIContainer.shared.nutritionRepository.saveDailyLog(userID: userID, log: log)
                    await MainActor.run {
                        AppLog.data.info("Journal entry deleted.")
                    }
                }
            } catch {
                await MainActor.run {
                    service.bannerService?.showBanner(title: "Error", message: "Failed to delete entry.", iconName: "xmark.circle.fill", iconColor: .red)
                    AppLog.data.error("Failed to delete journal entry: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
