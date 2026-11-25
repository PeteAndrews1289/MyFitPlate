import Foundation
import Combine
import CryptoKit

public struct WeightMeasurementDraft: Codable {
    public let id: String
    public let userID: String
    public let date: Date
    public let weightLbs: Double
    public let enteredValue: Double
    public let unit: String

    public static func importID(date: Date, weightLbs: Double) -> String {
        let input = "mfp:\(date.timeIntervalSince1970.bitPattern):\(weightLbs.bitPattern)"
        return "mfp-" + SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
public final class WeightSaveSession: ObservableObject {
    @Published public private(set) var draft: WeightMeasurementDraft?
    @Published public private(set) var isSaving = false
    @Published public private(set) var isAccepted = false
    @Published public private(set) var errorMessage: String?
    private let ownerID: String?
    private let store: EditorDraftStore
    private let scope: String
    private let measurementID: String?
    private var unreadable = false

    public init(userID: String?, store: EditorDraftStore = EditorDraftStore(), scope: String = "weight-measurement-save", measurementID: String? = nil) {
        self.scope = scope; self.measurementID = measurementID
        ownerID = userID; self.store = store
        guard let userID else { return }
        do { draft = try store.load(WeightMeasurementDraft.self, userID: userID, scope: scope)?.value } catch {
            unreadable = true; errorMessage = "The saved measurement could not be opened. It has been kept on this device."
        }
    }

    public func save(weightLbs: Double, enteredValue: Double, unit: String, date: Date,
                     using goals: GoalSettings, completion: @escaping (Bool) -> Void) {
        guard !isSaving, !isAccepted, !unreadable, let ownerID,
              DIContainer.shared.authService.currentUserID == ownerID,
              weightLbs.isFinite, weightLbs > 0, enteredValue.isFinite, enteredValue > 0,
              date.timeIntervalSince1970.isFinite else {
            errorMessage = "Check the measurement and sign back into the account that opened this entry."
            completion(false); return
        }
        let captured = draft ?? WeightMeasurementDraft(id: measurementID ?? UUID().uuidString, userID: ownerID, date: date,
                                                       weightLbs: weightLbs, enteredValue: enteredValue, unit: unit)
        guard captured.userID == ownerID, measurementID == nil || captured.id == measurementID else { completion(false); return }
        do { try store.save(captured, userID: ownerID, scope: scope); draft = captured } catch {
            errorMessage = "Could not keep this measurement on the device. Nothing was sent; retry safely."; completion(false); return
        }
        isSaving = true; errorMessage = nil
        goals.updateUserWeight(captured.weightLbs, date: captured.date, measurementID: captured.id) { [weak self] accepted in
            guard let self else { completion(false); return }
            self.isSaving = false
            guard DIContainer.shared.authService.currentUserID == ownerID else {
                self.errorMessage = "This measurement remains with its original account. Sign back in to finish saving."
                completion(false); return
            }
            guard accepted else { self.errorMessage = "Your measurement and original date are kept. Retry saving safely."; completion(false); return }
            do {
                try self.store.remove(userID: ownerID, scope: self.scope)
                self.isAccepted = true
                completion(true)
            } catch { self.errorMessage = "Weight was saved. Retry to clear the draft; it will not be added twice."; completion(false) }
        }
    }
}
