import Foundation
import FirebaseFirestore
import FirebaseAnalytics

class JournalEntryStore {
    private let db = Firestore.firestore()
    private weak var dailyLogService: DailyLogService?

    init(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }

    func addJournalEntry(for userID: String, entry: JournalEntry) async {
        guard let service = dailyLogService else { return }
        let dateToLog = service.activelyViewedDate
        let dateString = service.dateFormatter.string(from: dateToLog)
        let logRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs).document(dateString)

        do {
            let encodedEntry = try Firestore.Encoder().encode(entry)

            if service.currentDailyLog?.date == dateToLog {
                await MainActor.run {
                    if service.currentDailyLog?.journalEntries == nil {
                        service.currentDailyLog?.journalEntries = []
                    }
                    service.currentDailyLog?.journalEntries?.append(entry)
                }
            }

            try await logRef.updateData([
                "journalEntries": FieldValue.arrayUnion([encodedEntry])
            ])

            Analytics.logEvent("journal_entry_added", parameters: [
                "category": entry.category
            ])

            await MainActor.run {
                service.bannerService?.showBanner(title: "Success", message: "Journal entry saved!")
            }

        } catch let error as NSError where error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.notFound.rawValue {
            let newLog = DailyLog(id: dateString, date: dateToLog, meals: [], journalEntries: [entry])

            await MainActor.run {
                service.publishCurrentDailyLog(newLog)
            }

            do {
                try logRef.setData(from: newLog)
                Analytics.logEvent("journal_entry_added", parameters: [
                    "category": entry.category
                ])

                await MainActor.run {
                    service.bannerService?.showBanner(title: "Success", message: "Journal entry saved!")
                }
            } catch {
                AppLog.data.error("Failed to create log document for journal entry: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    service.bannerService?.showBanner(title: "Error", message: "Failed to save journal entry.", iconName: "xmark.circle.fill", iconColor: .red)
                }
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
        let dateString = service.dateFormatter.string(from: dateToLog)
        let logRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs).document(dateString)

        if service.currentDailyLog?.date == dateToLog,
           let index = service.currentDailyLog?.journalEntries?.firstIndex(where: { $0.id == entry.id }) {
            DispatchQueue.main.async {
                service.currentDailyLog?.journalEntries?.remove(at: index)
            }
        }

        do {
            let encodedEntry = try Firestore.Encoder().encode(entry)
            logRef.updateData([
                "journalEntries": FieldValue.arrayRemove([encodedEntry])
            ]) { error in
                Task { @MainActor in
                    if let error = error {
                        service.bannerService?.showBanner(title: "Error", message: "Failed to delete entry.", iconName: "xmark.circle.fill", iconColor: .red)
                        AppLog.data.error("Failed to delete journal entry: \(error.localizedDescription, privacy: .public)")
                    } else {
                        AppLog.data.info("Journal entry deleted.")
                    }
                }
            }
        } catch {
            Task { @MainActor in
                service.bannerService?.showBanner(title: "Error", message: "Failed to encode entry for deletion.", iconName: "xmark.circle.fill", iconColor: .red)
            }
        }
    }
}
