import Foundation
@MainActor
public class JournalEntryStore {
    private weak var dailyLogService: DailyLogService?

    public init(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }

    public func addJournalEntry(for userID: String, entry: JournalEntry) async {
        guard let service = dailyLogService else { return }
        let dateToLog = service.activelyViewedDate
        let dateString = service.dateFormatter.string(from: dateToLog)

        do {
            let logToSave: DailyLog
            if var currentLog = service.currentDailyLog,
               Calendar.current.isDate(currentLog.date, inSameDayAs: dateToLog) {
                if currentLog.journalEntries == nil {
                    currentLog.journalEntries = []
                }
                currentLog.journalEntries?.append(entry)
                logToSave = currentLog
            } else {
                logToSave = DailyLog(id: dateString, date: dateToLog, meals: [], journalEntries: [entry])
            }

            service.publishCurrentDailyLog(logToSave)
            try await DIContainer.shared.nutritionRepository.saveDailyLog(userID: userID, log: logToSave)

            DIContainer.shared.analyticsManager?.logEvent("journal_entry_added", parameters: [
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

    public func deleteJournalEntry(for userID: String, entry: JournalEntry) {
        guard let service = dailyLogService else { return }
        let dateToLog = service.activelyViewedDate

        guard var logToSave = service.currentDailyLog,
              Calendar.current.isDate(logToSave.date, inSameDayAs: dateToLog),
              let index = logToSave.journalEntries?.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        logToSave.journalEntries?.remove(at: index)
        service.publishCurrentDailyLog(logToSave)

        Task { @MainActor in
            do {
                try await DIContainer.shared.nutritionRepository.saveDailyLog(userID: userID, log: logToSave)
                AppLog.data.info("Journal entry deleted.")
            } catch {
                service.bannerService?.showBanner(title: "Error", message: "Failed to delete entry.", iconName: "xmark.circle.fill", iconColor: .red)
                AppLog.data.error("Failed to delete journal entry: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
