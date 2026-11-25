import Foundation

public struct ActivityEditPrecondition: Codable {
    public let expected: LoggedExercise
    public let desired: LoggedExercise
    public init(expected: LoggedExercise, desired: LoggedExercise) { self.expected = expected; self.desired = desired }

    public static func sameSnapshot(_ first: LoggedExercise, _ second: LoggedExercise) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard let left = try? encoder.encode(first), let right = try? encoder.encode(second) else { return false }
        return left == right
    }

    public func validate(in log: DailyLog) throws {
        let matches = (log.exercises ?? []).filter { $0.id == expected.id }
        guard !expected.id.isEmpty, expected.id == desired.id, expected.source == desired.source,
              expected.date == desired.date, expected.workoutID == desired.workoutID, expected.sessionID == desired.sessionID,
              matches.count == 1, let current = matches.first,
              Self.sameSnapshot(current, expected) || Self.sameSnapshot(current, desired) else {
            throw NSError(domain: "RunActivityEdit", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The linked activity changed or is missing. Review its current diary copy before retrying."])
        }
    }
}
