import Combine
import CryptoKit
import Foundation

public enum MaiaSavedCommand: Codable, Equatable {
    case water(ounces: Double)
    case workout(name: String, minutes: Int, calories: Double)
    case meal(FoodItem)
    case weight(pounds: Double)
    case startFast(hours: Int)
    case stopFast

    fileprivate var valid: Bool {
        switch self {
        case .water(let ounces): return ounces.isFinite && ounces > 0
        case .workout(let name, let minutes, let calories):
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && minutes > 0 && calories.isFinite && calories > 0
        case .meal(let food):
            return !food.name.isEmpty && [food.calories, food.protein, food.carbs, food.fats].allSatisfy { $0.isFinite && $0 >= 0 }
        case .weight(let pounds): return pounds.isFinite && pounds > 0
        case .startFast(let hours): return (1..<24).contains(hours)
        case .stopFast: return true
        }
    }

    fileprivate var signature: String? {
        var normalized = self
        if case .meal(var food) = self {
            food.id = ""
            food.timestamp = nil
            food.sourceMetadata = nil
            normalized = .meal(food)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(normalized)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }
}

public struct MaiaSavedActionReceipt: Codable {
    public let actionID: String
    public let entryID: String
    public private(set) var command: MaiaSavedCommand?
    public let date: Date
    public let mealName: String
    public let fastSessionID: UUID?
    public var isAccepted: Bool
    public private(set) var hasBeenSubmitted: Bool
    public private(set) var conversationCleared: Bool

    private enum CodingKeys: String, CodingKey {
        case actionID, entryID, command, date, mealName, fastSessionID, isAccepted, hasBeenSubmitted, conversationCleared
    }

    init(actionID: String, entryID: String, command: MaiaSavedCommand?, date: Date, mealName: String,
         fastSessionID: UUID?, isAccepted: Bool, hasBeenSubmitted: Bool = false, conversationCleared: Bool = false) {
        self.actionID = actionID; self.entryID = entryID; self.command = command; self.date = date
        self.mealName = mealName; self.fastSessionID = fastSessionID; self.isAccepted = isAccepted
        self.hasBeenSubmitted = hasBeenSubmitted; self.conversationCleared = conversationCleared
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        actionID = try values.decode(String.self, forKey: .actionID)
        entryID = try values.decode(String.self, forKey: .entryID)
        isAccepted = try values.decode(Bool.self, forKey: .isAccepted)
        command = try values.decodeIfPresent(MaiaSavedCommand.self, forKey: .command)
        date = try values.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
        mealName = try values.decodeIfPresent(String.self, forKey: .mealName) ?? ""
        fastSessionID = try values.decodeIfPresent(UUID.self, forKey: .fastSessionID)
        // Older receipts cannot prove that a write was never submitted.
        hasBeenSubmitted = try values.decodeIfPresent(Bool.self, forKey: .hasBeenSubmitted) ?? true
        conversationCleared = try values.decodeIfPresent(Bool.self, forKey: .conversationCleared) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(actionID, forKey: .actionID)
        try values.encode(entryID, forKey: .entryID)
        try values.encode(isAccepted, forKey: .isAccepted)
        guard command != nil else { return }
        try values.encode(command, forKey: .command)
        try values.encode(date, forKey: .date)
        try values.encode(mealName, forKey: .mealName)
        try values.encodeIfPresent(fastSessionID, forKey: .fastSessionID)
        try values.encode(hasBeenSubmitted, forKey: .hasBeenSubmitted)
        try values.encode(conversationCleared, forKey: .conversationCleared)
    }

    fileprivate func markingSubmitted() -> Self {
        var value = self; value.hasBeenSubmitted = true; return value
    }

    fileprivate func afterConversationClear() -> Self {
        if isAccepted {
            return Self(actionID: actionID, entryID: entryID, command: nil, date: .distantPast, mealName: "",
                        fastSessionID: nil, isAccepted: true, hasBeenSubmitted: true, conversationCleared: true)
        }
        var value = self; value.conversationCleared = true; return value
    }

    public var destinationDescription: String {
        let day = date.formatted(date: .abbreviated, time: .omitted)
        switch command {
        case .meal?: return "\(mealName) · \(day)"
        case .startFast?, .stopFast?: return "Fasting timer"
        case nil: return "Saved action"
        default: return day
        }
    }

    public var actionDescription: String {
        switch command {
        case .water(let ounces)?: return "\(ounces.formatted()) oz water"
        case .workout(let name, _, _)?: return name
        case .meal(let food)?: return food.name
        case .weight(let pounds)?: return "Weight: \(pounds.formatted()) lb"
        case .startFast(let hours)?: return "Start \(hours)-hour fast"
        case .stopFast?: return "End captured fast"
        case nil: return "Saved action"
        }
    }
}

public struct MaiaConversationClearReview {
    public fileprivate(set) var unsubmittedActions: [MaiaSavedActionReceipt] = []
    public fileprivate(set) var submittedActions: [MaiaSavedActionReceipt] = []
    public fileprivate(set) var acceptedActionCount = 0
    public fileprivate(set) var unreadableActionCount = 0
    public init() { }
}

/// Message/card identity is independent of the currently viewed day. Accepted receipts
/// remain available when a card is rendered again, while durable diary entry IDs make an
/// interrupted acknowledgement safe to replay without replacing later corrections.
@MainActor
public final class MaiaActionSaveSession: ObservableObject {
    public static let receiptDidChange = Notification.Name("MyFitPlate.maiaActionReceiptChanged")
    @Published public private(set) var receipt: MaiaSavedActionReceipt?
    @Published public private(set) var isSaving = false
    @Published public private(set) var errorMessage: String?
    public let actionID: String
    private let userID: String?
    private let store: EditorDraftStore
    private let transient: Bool
    private var unreadable = false
    private var weightSession: WeightSaveSession?
    private static let transientScope = "maia-pending-quick-action"
    private static let indexScope = "maia-action-index"

    private struct QuickActionPointer: Codable { let actionID: String }
    private var scope: String { "maia-action-\(actionID)" }

    public init(userID: String?, actionID: String?, store: EditorDraftStore = EditorDraftStore()) {
        self.userID = userID
        self.store = store
        transient = actionID == nil
        var selectedID = actionID ?? UUID().uuidString
        if actionID == nil, let userID {
            do {
                if let pointer = try store.load(QuickActionPointer.self, userID: userID, scope: Self.transientScope)?.value {
                    selectedID = pointer.actionID
                }
            } catch { unreadable = true; errorMessage = "The previous Maia action could not be opened. It is kept on this device." }
        }
        self.actionID = selectedID
        if let userID {
            do { receipt = try Self.loadReceipt(userID: userID, actionID: selectedID, store: store) } catch {
                unreadable = true; errorMessage = "The saved Maia action could not be opened. It has been kept unchanged."
            }
        }
    }

    public static func savedReceipt(userID: String?, actionID: String?, store: EditorDraftStore = EditorDraftStore()) -> MaiaSavedActionReceipt? {
        guard let userID, let actionID else { return nil }
        return try? loadReceipt(userID: userID, actionID: actionID, store: store)
    }

    /// The index also covers receipts whose message has fallen outside the saved chat window.
    public static func reviewConversationClear(userID: String, messages: [ChatMessage] = [],
                                               store: EditorDraftStore = EditorDraftStore()) throws -> MaiaConversationClearReview {
        guard DIContainer.shared.authService.currentUserID == userID else { throw CocoaError(.fileReadNoPermission) }
        var review = MaiaConversationClearReview()
        for actionID in try conversationActionIDs(userID: userID, messages: messages, store: store) {
            do {
                guard let receipt = try loadReceipt(userID: userID, actionID: actionID, store: store) else { continue }
                if receipt.isAccepted {
                    review.acceptedActionCount += 1
                } else if receipt.hasBeenSubmitted {
                    review.submittedActions.append(receipt)
                } else {
                    review.unsubmittedActions.append(receipt)
                }
            } catch { review.unreadableActionCount += 1 }
        }
        return review
    }

    /// Never removes a submitted command or changes diary/history data. The submitted
    /// marker is persisted before dispatch, so a missing acknowledgement stays reconcilable.
    public static func clearConversation(userID: String, messages: [ChatMessage], discardUnsubmitted: Bool,
                                         store: EditorDraftStore = EditorDraftStore()) throws {
        guard DIContainer.shared.authService.currentUserID == userID else { throw CocoaError(.fileWriteNoPermission) }
        let actionIDs = try conversationActionIDs(userID: userID, messages: messages, store: store)
        try store.save(actionIDs, userID: userID, scope: indexScope)
        for actionID in actionIDs {
            // Malformed/newer records stay unchanged and are disclosed in the review.
            guard let receipt = try? loadReceipt(userID: userID, actionID: actionID, store: store) else { continue }
            if !receipt.isAccepted, !receipt.hasBeenSubmitted, discardUnsubmitted {
                try store.remove(userID: userID, scope: "maia-action-\(actionID)")
                if let pointer = try store.load(QuickActionPointer.self, userID: userID, scope: transientScope)?.value,
                   pointer.actionID == actionID {
                    try store.remove(userID: userID, scope: transientScope)
                }
            } else {
                try store.save(receipt.afterConversationClear(), userID: userID, scope: "maia-action-\(actionID)")
            }
            NotificationCenter.default.post(name: receiptDidChange, object: nil, userInfo: ["actionID": actionID])
        }
    }

    private static func conversationActionIDs(userID: String, messages: [ChatMessage], store: EditorDraftStore) throws -> [String] {
        var actionIDs = Set(try store.load([String].self, userID: userID, scope: indexScope)?.value ?? [])
        let storedReceipts = try store.valuesMatchingScope(MaiaSavedActionReceipt.self, userID: userID) { "maia-action-\($0.actionID)" }
        actionIDs.formUnion(storedReceipts.map(\.actionID))
        if let pointer = try store.load(QuickActionPointer.self, userID: userID, scope: transientScope)?.value {
            actionIDs.insert(pointer.actionID)
        }
        let regex = try NSRegularExpression(pattern: "```json\\s*(\\{.*?\\})\\s*```", options: [.dotMatchesLineSeparators, .caseInsensitive])
        for message in messages where !message.isUser {
            actionIDs.insert("\(message.id.uuidString)-legacy-meal")
            let count = regex.numberOfMatches(in: message.text, range: NSRange(message.text.startIndex..., in: message.text))
            for index in 0..<count { actionIDs.insert("\(message.id.uuidString)-action-\(index)") }
        }
        return actionIDs.sorted()
    }

    private func registerAction(userID: String) throws {
        var actionIDs = try store.load([String].self, userID: userID, scope: Self.indexScope)?.value ?? []
        if !actionIDs.contains(actionID) {
            actionIDs.append(actionID)
            try store.save(actionIDs, userID: userID, scope: Self.indexScope)
        }
    }

    @discardableResult
    public func prepare(command: MaiaSavedCommand, date: Date, mealName: String, fastSessionID: UUID? = nil) -> Bool {
        guard usable, let userID, command.valid, Self.valid(date),
              !mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if errorMessage == nil { errorMessage = "Review this action's values before saving." }
            return false
        }
        let existing: MaiaSavedActionReceipt?
        do { existing = try Self.loadReceipt(userID: userID, actionID: actionID, store: store) } catch {
            unreadable = true
            errorMessage = "The saved action could not be opened. It has been kept unchanged."
            return false
        }
        do {
            try registerAction(userID: userID)
            if transient {
                if let pointer = try store.load(QuickActionPointer.self, userID: userID, scope: Self.transientScope)?.value {
                    guard pointer.actionID == actionID else {
                        errorMessage = "Finish the previous quick action before starting another."
                        return false
                    }
                } else {
                    try store.save(QuickActionPointer(actionID: actionID), userID: userID, scope: Self.transientScope)
                }
            }
            // Reload at command time so two pre-created card views agree on the first
            // durable capture rather than each inventing a day or logical entry.
            if let existing {
                guard existing.actionID == actionID, existing.isAccepted || existing.command?.signature == command.signature else {
                    errorMessage = "This card has an older pending action. Its original values are kept; review them before retrying."
                    return false
                }
                receipt = existing
            } else {
                let captured = MaiaSavedActionReceipt(actionID: actionID, entryID: Self.entryID(userID: userID, actionID: actionID), command: command,
                    date: date, mealName: mealName, fastSessionID: fastSessionID, isAccepted: false)
                try store.save(captured, userID: userID, scope: scope)
                receipt = captured
            }
            errorMessage = nil
            NotificationCenter.default.post(name: Self.receiptDidChange, object: nil, userInfo: ["actionID": actionID])
            return true
        } catch { errorMessage = "Could not keep this action on the device. Its previous record is unchanged; retry safely."; return false }
    }

    public func save(using service: DailyLogService, goals: GoalSettings?, waterGoal: Double,
                     external: ((MaiaSavedActionReceipt, @escaping (Bool) -> Void) -> Void)? = nil,
                     completion: @escaping (Bool) -> Void) {
        guard usable, !isSaving, let userID, service.isActiveAccount(userID) else { completion(false); return }
        let receipt: MaiaSavedActionReceipt
        do {
            guard let latest = try Self.loadReceipt(userID: userID, actionID: actionID, store: store) else {
                self.receipt = nil
                errorMessage = "This unsubmitted action was discarded."
                completion(false); return
            }
            receipt = latest
            self.receipt = latest
        } catch { errorMessage = "The saved action could not be opened. It has been kept unchanged."; completion(false); return }
        if receipt.isAccepted { completion(finishTransient()); return }
        guard let command = receipt.command else { completion(false); return }
        do {
            let submitted = receipt.markingSubmitted()
            try store.save(submitted, userID: userID, scope: scope)
            self.receipt = submitted
        } catch { errorMessage = "Could not keep this action on the device. Nothing was sent; retry safely."; completion(false); return }
        isSaving = true
        let finished: (Bool) -> Void = { [weak self] accepted in
            guard let self else { completion(false); return }
            self.isSaving = false
            guard self.usable else { completion(false); return }
            guard accepted else {
                self.errorMessage = self.weightSession?.errorMessage ?? "Your action and original date are kept. Retry safely."
                completion(false)
                return
            }
            do {
                // Clear-chat may have marked this in-flight operation for minimization.
                guard var acceptedReceipt = try Self.loadReceipt(userID: userID, actionID: self.actionID, store: self.store) else {
                    throw CocoaError(.fileReadNoSuchFile)
                }
                acceptedReceipt.isAccepted = true
                if acceptedReceipt.conversationCleared { acceptedReceipt = acceptedReceipt.afterConversationClear() }
                try self.store.save(acceptedReceipt, userID: userID, scope: self.scope)
                self.receipt = acceptedReceipt
                self.errorMessage = nil
                NotificationCenter.default.post(name: Self.receiptDidChange, object: nil, userInfo: ["actionID": self.actionID])
                completion(self.finishTransient())
            } catch { self.errorMessage = "Your action was saved. Retry to finish its receipt without adding it twice."; completion(false) }
        }
        switch command {
        case .water(let ounces):
            service.addWaterToLog(for: userID, amount: ounces, goalOunces: waterGoal,
                                 capturedAt: receipt.date, entryID: receipt.entryID, completion: finished)
        case .workout(let name, let minutes, let calories):
            let exercise = LoggedExercise(id: receipt.entryID, name: name, durationMinutes: minutes,
                                          caloriesBurned: calories, date: receipt.date, source: "maia")
            Task { finished(await service.saveWorkoutExercise(for: userID, exercise: exercise)) }
        case .meal(var food):
            food.id = receipt.entryID
            food.timestamp = receipt.date
            service.addMealGroupsToLog(for: userID, date: receipt.date, mealGroups: [(mealName: receipt.mealName, foodItems: [food])],
                                       source: "ai_chat", deduplicateFoodIDs: true, completion: finished)
        case .weight(let pounds):
            guard let goals else { finished(false); return }
            let session = WeightSaveSession(userID: userID, store: store, scope: "maia-weight-\(actionID)", measurementID: receipt.entryID)
            weightSession = session
            session.save(weightLbs: pounds, enteredValue: pounds, unit: "lb", date: receipt.date, using: goals, completion: finished)
        case .startFast, .stopFast:
            guard let external else { finished(false); return }
            external(receipt, finished)
        }
    }

    private var usable: Bool {
        guard !unreadable, let userID, DIContainer.shared.authService.currentUserID == userID else {
            if !unreadable { errorMessage = "Sign back into the account that opened this Maia action." }
            return false
        }
        return true
    }

    private static func entryID(userID: String, actionID: String) -> String {
        "maia-" + SHA256.hash(data: Data("\(userID)|\(actionID)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func valid(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && date >= .distantPast && date <= .distantFuture
    }

    private static func loadReceipt(userID: String, actionID: String, store: EditorDraftStore) throws -> MaiaSavedActionReceipt? {
        guard let receipt = try store.load(MaiaSavedActionReceipt.self, userID: userID, scope: "maia-action-\(actionID)")?.value else { return nil }
        guard receipt.actionID == actionID, receipt.entryID == entryID(userID: userID, actionID: actionID),
              (receipt.command == nil && receipt.isAccepted) ||
                (receipt.command?.valid == true && valid(receipt.date) && !receipt.mealName.isEmpty) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return receipt
    }

    private func finishTransient() -> Bool {
        guard transient, let userID else { return true }
        do {
            if let pointer = try store.load(QuickActionPointer.self, userID: userID, scope: Self.transientScope)?.value, pointer.actionID == actionID {
                try store.remove(userID: userID, scope: Self.transientScope)
            }
            return true
        } catch { errorMessage = "Your action was saved. Retry to clear its receipt safely."; return false }
    }
}
