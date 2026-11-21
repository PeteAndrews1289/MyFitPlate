import CryptoKit
import Foundation

public enum DiaryTransferMode: String, Codable, Sendable { case copy, move }

public enum DiaryTransferError: LocalizedError, Equatable {
    case invalid, changed, accountChanged, pendingWrites, unsupported, receiptMismatch, receiptMissing, alreadyUndone, cancelled, tooLarge, futureDay

    public var errorDescription: String? {
        switch self {
        case .invalid: return "Review the selected foods, portions and destination before continuing."
        case .changed: return "A selected food changed or was removed. Nothing was transferred; review the current diary."
        case .accountChanged: return "Sign back into the account that opened this transfer."
        case .pendingWrites: return "These diary days still have changes waiting to sync. Finish syncing, then retry."
        case .unsupported: return "This connection cannot safely transfer diary foods. Nothing was changed."
        case .receiptMismatch: return "The saved transfer could not be verified. It has been kept unchanged."
        case .receiptMissing: return "This transfer has not been confirmed. Its pending review is kept for retry."
        case .alreadyUndone: return "This transfer has already been undone."
        case .cancelled: return "This pending transfer was cancelled. No foods were transferred."
        case .tooLarge: return "Transfer fewer foods at a time. Your diary has not changed."
        case .futureDay: return "Choose today or an earlier diary day before transferring these foods."
        }
    }
}

/// A local review proposal. Copy identities are assigned once, before submission;
/// changing inclusion, portion or meal never creates a new retry identity.
public struct DiaryTransferDraft: Codable, Identifiable {
    public let id: UUID
    public let source: DiaryDayContext
    public var destination: DiaryDayContext
    public let mode: DiaryTransferMode
    public var entries: [Entry]

    public struct Entry: Codable, Identifiable {
        public var id: String { originalFood.id }
        public let originalFood: FoodItem
        public let originalMealID: UUID
        public let originalMealName: String
        public let destinationFoodID: String
        public var isIncluded: Bool
        public var multiplier: Double
        public var destinationMealName: String
        public let proposedMealID: UUID
    }

    public init(source: DiaryDayContext, destination: DiaryDayContext, sourceLog: DailyLog,
                mode: DiaryTransferMode, foodIDs: [String]? = nil) throws {
        guard source.userID == destination.userID, sourceLog.id == source.dayKey else { throw DiaryTransferError.invalid }
        let requested = foodIDs.map { Set($0) }
        let foods = sourceLog.meals.flatMap(\.foodItems)
        guard Set(foods.map(\.id)).count == foods.count,
              requested.map({ !$0.isEmpty && $0.isSubset(of: Set(foods.map(\.id))) }) ?? !foods.isEmpty else {
            throw DiaryTransferError.invalid
        }
        id = UUID(); self.source = source; self.destination = destination; self.mode = mode
        entries = sourceLog.meals.flatMap { meal in
            meal.foodItems.filter { requested?.contains($0.id) ?? true }.map { food in
                Entry(originalFood: food, originalMealID: meal.id, originalMealName: meal.name,
                      destinationFoodID: mode == .copy ? UUID().uuidString : food.id,
                      isIncluded: true, multiplier: 1, destinationMealName: meal.name, proposedMealID: UUID())
            }
        }
    }

    /// Rebuild only the locked presentation for an existing remote receipt. No food,
    /// operation, meal or consumption identity is regenerated for historical Undo.
    public init(resuming command: DiaryTransferCommand) throws {
        try command.validate()
        id = command.id; source = command.source; destination = command.destination; mode = command.mode
        entries = command.entries.map { entry in
            Entry(originalFood: entry.originalFood, originalMealID: entry.originalMealID,
                  originalMealName: entry.originalMealName, destinationFoodID: entry.destinationFood.id,
                  isIncluded: true, multiplier: entry.multiplier, destinationMealName: entry.destinationMealName,
                  proposedMealID: entry.proposedMealID)
        }
    }

    public func freeze(now: Date = Date()) throws -> DiaryTransferCommand {
        guard !destination.isFuture(now: now) else { throw DiaryTransferError.futureDay }
        let selections = try entries.filter(\.isIncluded).map { entry -> DiaryTransferCommand.Entry in
            guard entry.multiplier.isFinite, entry.multiplier > 0,
                  mode == .copy || entry.multiplier == 1,
                  var desired = FoodRepeatRules.adjusting(entry.originalFood, by: entry.multiplier) else {
                throw DiaryTransferError.invalid
            }
            desired.id = entry.destinationFoodID
            if mode == .copy { desired.timestamp = try copyTimestamp(now: now) }
            return DiaryTransferCommand.Entry(originalFood: entry.originalFood,
                originalMealID: entry.originalMealID, originalMealName: entry.originalMealName,
                destinationFood: desired, destinationMealName: entry.destinationMealName,
                proposedMealID: entry.proposedMealID, multiplier: entry.multiplier)
        }
        return try DiaryTransferCommand(id: id, source: source, destination: destination, mode: mode, entries: selections)
    }

    private func copyTimestamp(now: Date) throws -> Date {
        if destination.isToday(now: now) {
            return Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        }
        let time = destination.calendar.dateComponents([.hour, .minute, .second], from: now)
        let anchored = destination.calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0,
            second: time.second ?? 0, of: destination.displayDate) ?? destination.displayDate
        guard DiaryDayContext.dayKey(for: anchored, timeZone: destination.timeZone) == destination.dayKey else {
            throw DiaryTransferError.invalid
        }
        return anchored
    }
}

public struct DiaryTransferCommand: Codable, Identifiable {
    public let schemaVersion: Int
    public let id: UUID
    public let source: DiaryDayContext
    public let destination: DiaryDayContext
    public let mode: DiaryTransferMode
    public let entries: [Entry]
    public var userID: String { source.userID }
    public var isSameDay: Bool { source.dayKey == destination.dayKey }

    public struct Entry: Codable {
        public let originalFood: FoodItem
        public let originalMealID: UUID
        public let originalMealName: String
        public let destinationFood: FoodItem
        public let destinationMealName: String
        public let proposedMealID: UUID
        public let multiplier: Double

        public init(originalFood: FoodItem, originalMealID: UUID, originalMealName: String,
                    destinationFood: FoodItem, destinationMealName: String, proposedMealID: UUID = UUID(), multiplier: Double = 1) {
            self.originalFood = originalFood; self.originalMealID = originalMealID; self.originalMealName = originalMealName
            self.destinationFood = destinationFood; self.destinationMealName = destinationMealName; self.proposedMealID = proposedMealID
            self.multiplier = multiplier
        }
    }

    public init(id: UUID = UUID(), source: DiaryDayContext, destination: DiaryDayContext,
                mode: DiaryTransferMode, entries: [Entry], schemaVersion: Int = 1) throws {
        self.schemaVersion = schemaVersion
        self.id = id; self.source = source; self.destination = destination; self.mode = mode; self.entries = entries
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw DiaryTransferError.receiptMismatch }
        guard source.userID == destination.userID, !entries.isEmpty,
              Set(entries.map { $0.originalFood.id }).count == entries.count,
              Set(entries.map { $0.destinationFood.id }).count == entries.count else { throw DiaryTransferError.invalid }
        guard entries.count <= 100 else { throw DiaryTransferError.tooLarge }
        for entry in entries {
            guard !entry.originalFood.id.isEmpty, !entry.destinationFood.id.isEmpty,
                  !entry.destinationMealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.originalMealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.multiplier.isFinite, entry.multiplier > 0,
                  (try? JSONEncoder().encode(entry.destinationFood)) != nil else { throw DiaryTransferError.invalid }
            if mode == .move {
                guard entry.multiplier == 1, FoodEditPrecondition.sameSnapshot(entry.originalFood, entry.destinationFood),
                      !isSameDay || entry.originalMealName.caseInsensitiveCompare(entry.destinationMealName) != .orderedSame else {
                    throw DiaryTransferError.invalid
                }
            } else {
                guard !entries.contains(where: { $0.originalFood.id == entry.destinationFood.id }),
                      var expected = FoodRepeatRules.adjusting(entry.originalFood, by: entry.multiplier),
                      let timestamp = entry.destinationFood.timestamp,
                      timestamp.timeIntervalSince1970 == floor(timestamp.timeIntervalSince1970),
                      DiaryDayContext.dayKey(for: timestamp, timeZone: destination.timeZone) == destination.dayKey else {
                    throw DiaryTransferError.invalid
                }
                expected.id = entry.destinationFood.id; expected.timestamp = timestamp
                guard FoodEditPrecondition.sameSnapshot(expected, entry.destinationFood) else { throw DiaryTransferError.invalid }
            }
        }
        guard try JSONEncoder().encode(self).count <= 200_000 else { throw DiaryTransferError.tooLarge }
    }

    public func fingerprint() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(self)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct DiaryTransferReceipt: Codable, Identifiable {
    public var id: UUID { command.id }
    public let command: DiaryTransferCommand
    public let commandFingerprint: String
    public let acceptedAt: Date
    public var undoneAt: Date?
    public let placements: [Placement]

    public struct Placement: Codable {
        public let originalFood: FoodItem
        public let originalMealID: UUID
        public let originalMealName: String
        public let destinationFood: FoodItem
        public let destinationMealID: UUID
        public let destinationMealName: String
    }

    public func validate() throws {
        try command.validate()
        guard commandFingerprint == (try command.fingerprint()), placements.count == command.entries.count else {
            throw DiaryTransferError.receiptMismatch
        }
        for (entry, placement) in zip(command.entries, placements) {
            guard FoodEditPrecondition.sameSnapshot(entry.originalFood, placement.originalFood),
                  FoodEditPrecondition.sameSnapshot(entry.destinationFood, placement.destinationFood),
                  entry.originalMealID == placement.originalMealID,
                  entry.originalMealName == placement.originalMealName,
                  entry.destinationMealName.caseInsensitiveCompare(placement.destinationMealName) == .orderedSame else {
                throw DiaryTransferError.receiptMismatch
            }
        }
        guard try JSONEncoder().encode(self).count <= 500_000 else { throw DiaryTransferError.tooLarge }
    }
}

/// A permanent receipt at the same operation path fences out a late commit from a
/// previously interrupted client. Absence alone is never proof that retry is safe.
public struct DiaryTransferCancellation: Codable {
    public let isCancelled: Bool
    public let command: DiaryTransferCommand
    public let commandFingerprint: String
    public let cancelledAt: Date

    public init(command: DiaryTransferCommand, now: Date = Date()) throws {
        try command.validate()
        isCancelled = true; self.command = command; commandFingerprint = try command.fingerprint(); cancelledAt = now
    }

    public func validate(for command: DiaryTransferCommand) throws {
        try self.command.validate()
        guard isCancelled, self.command.id == command.id,
              commandFingerprint == (try self.command.fingerprint()), commandFingerprint == (try command.fingerprint()) else {
            throw DiaryTransferError.receiptMismatch
        }
    }
}

public struct DiaryTransferResult: Codable {
    public let receipt: DiaryTransferReceipt
    public let sourceLog: DailyLog
    public let destinationLog: DailyLog
    public let newlyApplied: Bool

    public init(receipt: DiaryTransferReceipt, sourceLog: DailyLog, destinationLog: DailyLog, newlyApplied: Bool) {
        self.receipt = receipt; self.sourceLog = sourceLog; self.destinationLog = destinationLog; self.newlyApplied = newlyApplied
    }
}

/// Pure transaction body shared by the committed repository and its test double.
/// Only selected food entries change. Other foods, exercise, water, day reviews and
/// optional/manual totals come from the latest documents, never the proposal.
public enum DiaryTransferRules {
    public static func apply(_ command: DiaryTransferCommand, source: DailyLog, destination: DailyLog,
                             now: Date = Date()) throws -> DiaryTransferResult {
        try command.validate()
        try validateLogs(command, source: source, destination: destination)
        for entry in command.entries {
            try require(entry.originalFood, mealID: entry.originalMealID, in: source)
        }
        var nextSource = source
        var nextDestination = command.isSameDay ? source : destination
        if command.mode == .move {
            remove(command.entries.map { $0.originalFood.id }, from: &nextSource)
            if command.isSameDay { nextDestination = nextSource }
        }
        let occupied = Set(nextDestination.meals.flatMap(\.foodItems).map(\.id))
        guard command.entries.allSatisfy({ !occupied.contains($0.destinationFood.id) }) else { throw DiaryTransferError.changed }
        var placements: [DiaryTransferReceipt.Placement] = []
        for entry in command.entries {
            let index = try destinationMeal(named: entry.destinationMealName, proposedID: entry.proposedMealID, in: &nextDestination)
            nextDestination.meals[index].foodItems.append(entry.destinationFood)
            placements.append(DiaryTransferReceipt.Placement(originalFood: entry.originalFood,
                originalMealID: entry.originalMealID, originalMealName: entry.originalMealName,
                destinationFood: entry.destinationFood, destinationMealID: nextDestination.meals[index].id,
                destinationMealName: nextDestination.meals[index].name))
        }
        if command.isSameDay { nextSource = nextDestination }
        let receipt = DiaryTransferReceipt(command: command, commandFingerprint: try command.fingerprint(), acceptedAt: now,
                                           placements: placements)
        try receipt.validate()
        return DiaryTransferResult(receipt: receipt, sourceLog: nextSource.rememberingMutationBase(),
                                   destinationLog: nextDestination.rememberingMutationBase(), newlyApplied: true)
    }

    public static func undo(_ receipt: DiaryTransferReceipt, source: DailyLog, destination: DailyLog,
                            now: Date = Date()) throws -> DiaryTransferResult {
        try receipt.validate()
        let command = receipt.command
        try validateLogs(command, source: source, destination: destination)
        if receipt.undoneAt != nil { return DiaryTransferResult(receipt: receipt, sourceLog: source, destinationLog: destination, newlyApplied: false) }
        for placement in receipt.placements {
            try require(placement.destinationFood, mealID: placement.destinationMealID, in: destination)
        }
        var nextSource = source
        var nextDestination = destination
        remove(receipt.placements.map { $0.destinationFood.id }, from: &nextDestination)
        if command.isSameDay { nextSource = nextDestination }
        if command.mode == .move {
            let occupied = Set(nextSource.meals.flatMap(\.foodItems).map(\.id))
            guard receipt.placements.allSatisfy({ !occupied.contains($0.originalFood.id) }) else { throw DiaryTransferError.changed }
            for placement in receipt.placements {
                let index: Int
                if let existing = nextSource.meals.firstIndex(where: { $0.id == placement.originalMealID }) { index = existing } else {
                    nextSource.meals.append(Meal(id: placement.originalMealID, name: placement.originalMealName))
                    index = nextSource.meals.count - 1
                }
                nextSource.meals[index].foodItems.append(placement.originalFood)
            }
        }
        if command.isSameDay { nextDestination = nextSource }
        var undone = receipt; undone.undoneAt = now
        return DiaryTransferResult(receipt: undone, sourceLog: nextSource.rememberingMutationBase(),
                                   destinationLog: nextDestination.rememberingMutationBase(), newlyApplied: true)
    }

    private static func validateLogs(_ command: DiaryTransferCommand, source: DailyLog, destination: DailyLog) throws {
        guard source.id == command.source.dayKey, destination.id == command.destination.dayKey,
              command.isSameDay == (source.id == destination.id) else { throw DiaryTransferError.invalid }
        for log in command.isSameDay ? [source] : [source, destination] {
            let ids = log.meals.flatMap(\.foodItems).map(\.id)
            guard Set(ids).count == ids.count, Set(log.meals.map(\.id)).count == log.meals.count else { throw DiaryTransferError.changed }
        }
    }

    private static func require(_ food: FoodItem, mealID: UUID, in log: DailyLog) throws {
        let matches = log.meals.flatMap { meal in meal.foodItems.filter { $0.id == food.id }.map { (meal.id, $0) } }
        guard matches.count == 1, matches[0].0 == mealID, FoodEditPrecondition.sameSnapshot(matches[0].1, food) else {
            throw DiaryTransferError.changed
        }
    }

    private static func remove(_ ids: [String], from log: inout DailyLog) {
        let ids = Set(ids)
        for index in log.meals.indices { log.meals[index].foodItems.removeAll { ids.contains($0.id) } }
    }

    private static func destinationMeal(named name: String, proposedID: UUID, in log: inout DailyLog) throws -> Int {
        let matches = log.meals.indices.filter { log.meals[$0].name.caseInsensitiveCompare(name) == .orderedSame }
        guard matches.count <= 1 else { throw DiaryTransferError.changed }
        if let index = matches.first { return index }
        guard !log.meals.contains(where: { $0.id == proposedID }) else { throw DiaryTransferError.changed }
        log.meals.append(Meal(id: proposedID, name: name))
        return log.meals.count - 1
    }
}
