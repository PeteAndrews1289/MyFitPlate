import Foundation

public enum RunTrainingBlockRules {
    public static func make(brief: RunTrainingBlockBrief, strengthDays: Set<TrainingCalendarDay>,
                            commitments: [TrainingRunCommitment] = [], now: Date = Date(), calendar: Calendar = .current) throws -> RunTrainingBlock {
        guard let start = brief.start.date(calendar: calendar), TrainingCalendarDay(start, calendar: calendar) == brief.start,
              start >= calendar.startOfDay(for: now), (4...8).contains(brief.weeks),
              brief.recentWeeklyMinutes.isFinite, (20...900).contains(brief.recentWeeklyMinutes),
              brief.recentLongestMinutes.isFinite, (10...180).contains(brief.recentLongestMinutes),
              brief.recentLongestMinutes <= brief.recentWeeklyMinutes,
              (2...4).contains(brief.weekdays.count), Set(brief.weekdays).count == brief.weekdays.count,
              brief.weekdays.allSatisfy({ (1...7).contains($0) }), brief.weekdays.contains(brief.preferredLongWeekday) else {
            throw RunTrainingBlockError.invalid
        }
        if let targetDay = brief.targetDay {
            guard let target = targetDay.date(calendar: calendar), TrainingCalendarDay(target, calendar: calendar) == targetDay,
                  let end = calendar.date(byAdding: .day, value: brief.weeks * 7 - 1, to: start), target >= end else {
                throw RunTrainingBlockError.conflict("Choose a goal date after this block, or review the block's start and length.")
            }
        }
        var slots: [RunTrainingBlockSlot] = [], ceilings: [Double] = [], notices = Set<String>()
        var normalTarget = brief.recentWeeklyMinutes
        for week in 0..<brief.weeks {
            let dates = (0..<7).compactMap { offset -> Date? in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + offset, to: start),
                      brief.weekdays.contains(calendar.component(.weekday, from: date)) else { return nil }
                let day = TrainingCalendarDay(date, calendar: calendar)
                guard !strengthDays.contains(day), !commitments.contains(where: { $0.day == day }) else {
                    notices.insert("Existing strength and scheduled runs keep their dates; conflicting run days are left open.")
                    return nil
                }
                return date
            }
            guard dates.count >= 2 else { throw RunTrainingBlockError.conflict("Week \(week + 1) has fewer than two available days after protecting strength and existing runs. Choose different days before building.") }
            let recoveryWeek = week % 4 == 3
            if week > 0 && !recoveryWeek && week % 4 != 0 { normalTarget *= 1.05 }
            let ceiling = min(normalTarget * (recoveryWeek ? 0.75 : 1), Double(dates.count) * min(180, brief.recentLongestMinutes * pow(1.05, Double(week))))
            ceilings.append(ceiling)
            let longIndex = dates.firstIndex { calendar.component(.weekday, from: $0) == brief.preferredLongWeekday } ?? dates.count - 1
            let qualityIndex = brief.includeQuality && brief.ability == .established && !recoveryWeek && week > 0
                ? dates.indices.first(where: { index in
                    guard index != longIndex else { return false }
                    let day = dates[index]
                    let longGap = abs(calendar.dateComponents([.day], from: day, to: dates[longIndex]).day ?? 0)
                    return longGap >= 2 && !strengthDays.contains(where: { value in
                        guard let date = value.date(calendar: calendar) else { return true }
                        return abs(calendar.dateComponents([.day], from: day, to: date).day ?? 0) <= 1
                    })
                }) : nil
            if brief.includeQuality && qualityIndex == nil { notices.insert("Quality work is omitted when experience, recovery week or strength spacing does not support it. Easy sessions remain available.") }
            let weights = dates.indices.map { $0 == longIndex && !recoveryWeek ? 1.35 : 1.0 }
            let sum = weights.reduce(0, +)
            for index in dates.indices {
                let minutes = floor(min(ceiling * weights[index] / sum,
                    brief.recentLongestMinutes * pow(1.05, Double(week))))
                guard minutes >= 8 else { throw RunTrainingBlockError.conflict("The confirmed weekly baseline is too small for this many sessions. Select fewer days or review your baseline; no extra workload was added.") }
                let role: RunBlockRole = brief.ability == .starting ? .runWalk : recoveryWeek ? .recovery
                    : index == qualityIndex ? .quality : index == longIndex ? .long : .easy
                let id = UUID().uuidString
                slots.append(.init(id: id, revisionID: UUID().uuidString, weekIndex: week,
                    day: TrainingCalendarDay(dates[index], calendar: calendar), role: role,
                    plan: workout(id: id, role: role, minutes: minutes), outcome: nil))
            }
        }
        notices.insert("Time-based progression uses your confirmed baseline, a 5% planning ceiling in build weeks and every fourth week lighter. These are transparent planning limits, not a race-time or injury-prevention promise.")
        let block = RunTrainingBlock(brief: brief, slots: slots, ceilings: ceilings, notes: notices.sorted(), now: now)
        try validateChange(from: nil, to: block, strengthDays: strengthDays, otherCommitments: commitments, now: now, calendar: calendar)
        return block
    }

    public enum Adjustment { case move(TrainingCalendarDay), shorten(minutes: Double), easier, skip, lighterWeek(Int) }
    public static func review(block: RunTrainingBlock, slotID: String, adjustment: Adjustment, ownerID: String,
                              strengthDays: Set<TrainingCalendarDay>, otherCommitments: [TrainingRunCommitment] = [],
                              now: Date = Date(), calendar: Calendar = .current) throws -> RunTrainingBlockChange {
        guard !ownerID.isEmpty, !block.archived, let index = block.slots.firstIndex(where: { $0.id == slotID }) else { throw RunTrainingBlockError.invalid }
        guard block.slots[index].canChange else { throw RunTrainingBlockError.completed }
        var after = block
        let original = block.slots[index]
        let explanation: String
        switch adjustment {
        case .move(let day):
            guard let date = day.date(calendar: calendar), TrainingCalendarDay(date, calendar: calendar) == day,
                  day != original.day, date >= calendar.startOfDay(for: now), let week = weekIndex(date, in: block, calendar: calendar),
                  briefAllows(day: date, brief: block.brief, calendar: calendar) else { throw RunTrainingBlockError.invalid }
            after.slots[index].day = day; after.slots[index].weekIndex = week
            explanation = "Move only this run. Other sessions, recorded outcomes and daily nutrition stay unchanged."
        case .shorten(let minutes):
            guard minutes.isFinite, minutes >= 8, minutes < original.plannedMinutes,
                  original.day.date(calendar: calendar).map({ $0 >= calendar.startOfDay(for: now) }) == true else { throw RunTrainingBlockError.invalid }
            after.slots[index].plan = workout(id: original.plan.id, role: original.role, minutes: minutes)
            explanation = "Shorten only this future run from \(Int(original.plannedMinutes)) to \(Int(minutes)) minutes."
        case .easier:
            guard original.day.date(calendar: calendar).map({ $0 >= calendar.startOfDay(for: now) }) == true else { throw RunTrainingBlockError.invalid }
            after.slots[index].role = block.brief.ability == .starting ? .runWalk : .easy
            after.slots[index].plan = workout(id: original.plan.id, role: after.slots[index].role, minutes: original.plannedMinutes)
            explanation = "Keep this run's date and duration, with easy effort throughout."
        case .skip:
            after.slots[index].outcome = .init(state: .skipped, acceptedAt: now)
            explanation = "Record this planned run as skipped. It creates no workout and adds no catch-up session."
        case .lighterWeek(let week):
            guard (0..<block.brief.weeks).contains(week) else { throw RunTrainingBlockError.invalid }
            for slotIndex in after.slots.indices where after.slots[slotIndex].weekIndex == week && after.slots[slotIndex].canChange {
                guard after.slots[slotIndex].day.date(calendar: calendar).map({ $0 >= calendar.startOfDay(for: now) }) == true else { continue }
                after.slots[slotIndex].role = block.brief.ability == .starting ? .runWalk : .recovery
                after.slots[slotIndex].plan = workout(id: after.slots[slotIndex].plan.id, role: after.slots[slotIndex].role,
                    minutes: max(8, floor(after.slots[slotIndex].plannedMinutes * 0.8)))
                after.slots[slotIndex].revisionID = UUID().uuidString
            }
            explanation = "Review a lighter week: reduce only future unstarted sessions, keeping completed and skipped outcomes intact."
        }
        if case .lighterWeek = adjustment {} else { after.slots[index].revisionID = UUID().uuidString }
        after.revisionID = UUID().uuidString
        try validateChange(from: block, to: after, strengthDays: strengthDays, otherCommitments: otherCommitments, now: now, calendar: calendar)
        return .init(ownerID: ownerID, before: block, after: after, explanation: explanation)
    }

    public static func validateChange(from before: RunTrainingBlock?, to after: RunTrainingBlock,
                                      strengthDays: Set<TrainingCalendarDay>, otherCommitments: [TrainingRunCommitment],
                                      now: Date = Date(), calendar: Calendar = .current) throws {
        guard after.schemaVersion == 1, !after.id.isEmpty, !after.revisionID.isEmpty,
              after.weeklyMinuteCeilings.count == after.brief.weeks, Set(after.slots.map(\.id)).count == after.slots.count,
              after.weeklyMinuteCeilings.allSatisfy({ $0.isFinite && $0 >= 0 }),
              !after.slots.isEmpty, after.slots.count <= 32 else { throw RunTrainingBlockError.invalid }
        if let before {
            guard before.id == after.id, before.brief == after.brief,
                  Set(before.slots.map(\.id)) == Set(after.slots.map(\.id)),
                  before.weeklyMinuteCeilings == after.weeklyMinuteCeilings,
                  before.slots.filter({ !$0.canChange }).allSatisfy({ old in after.slots.first { $0.id == old.id } == old }) else {
                throw RunTrainingBlockError.completed
            }
        }
        let future = after.slots.filter { $0.canChange }
        guard Set(future.map(\.day)).count == future.count else { throw RunTrainingBlockError.conflict("Two planned runs would occupy the same day. Review one move at a time.") }
        for slot in future {
            guard let date = slot.day.date(calendar: calendar), slot.plannedMinutes.isFinite,
                  slot.plannedMinutes >= 8, slot.plannedMinutes <= 180, !slot.plan.steps.isEmpty,
                  slot.plan.steps.allSatisfy({ step in
                      if case .duration(let seconds) = step.goal { return seconds.isFinite && seconds > 0 }
                      return false
                  }) else { throw RunTrainingBlockError.invalid }
            guard slot.weekIndex == weekIndex(date, in: after, calendar: calendar),
                  briefAllows(day: date, brief: after.brief, calendar: calendar),
                  Set(slot.plan.steps.map(\.id)).count == slot.plan.steps.count else { throw RunTrainingBlockError.invalid }
            let changed = before?.slots.first(where: { $0.id == slot.id }) != slot
            guard changed else { continue }
            if date >= calendar.startOfDay(for: now) {
                let closeStrength = strengthDays.contains { day in
                    day.date(calendar: calendar).map { abs(calendar.dateComponents([.day], from: date, to: $0).day ?? 0) <= 1 } ?? true
                }
                let closeDemanding = future.contains { other in
                    guard other.id != slot.id, (slot.role == .quality && [.quality, .long].contains(other.role))
                        || (slot.role == .long && other.role == .quality), let otherDate = other.day.date(calendar: calendar) else { return false }
                    return abs(calendar.dateComponents([.day], from: date, to: otherDate).day ?? 0) <= 1
                }
                guard (slot.role != .quality || !closeStrength) && !closeDemanding else {
                    throw RunTrainingBlockError.conflict("Keep quality work away from strength and longer runs. Choose another day or review an easier session.")
                }
                guard !strengthDays.contains(slot.day), !otherCommitments.contains(where: { $0.id != slot.id && $0.day == slot.day }) else {
                    throw RunTrainingBlockError.conflict("That day already has strength or another scheduled run. Choose another available day; existing training stays intact.")
                }
            }
        }
        for week in 0..<after.brief.weeks {
            let total = plannedMinutes(after, week: week)
            let old = before.map { plannedMinutes($0, week: week) } ?? 0
            guard total <= after.weeklyMinuteCeilings[week] + 0.01 || total <= old + 0.01 else { throw RunTrainingBlockError.overload }
        }
    }
    public static func plannedMinutes(_ block: RunTrainingBlock, week: Int) -> Double {
        block.slots.filter { $0.weekIndex == week }.reduce(0) { total, slot in
            if slot.outcome?.state == .skipped { return total }
            return total + (slot.outcome?.movingSeconds.map { $0 / 60 } ?? slot.plannedMinutes)
        }
    }
    private static func briefAllows(day: Date, brief: RunTrainingBlockBrief, calendar: Calendar) -> Bool {
        brief.weekdays.contains(calendar.component(.weekday, from: day))
    }
    private static func weekIndex(_ date: Date, in block: RunTrainingBlock, calendar: Calendar) -> Int? {
        guard let start = block.brief.start.date(calendar: calendar), let days = calendar.dateComponents([.day], from: start, to: date).day,
              days >= 0, days < block.brief.weeks * 7 else { return nil }
        return days / 7
    }
    static func workout(id: String, role: RunBlockRole, minutes: Double) -> RunWorkoutPlan {
        let total = floor(minutes) * 60, edge = min(300, total * 0.15)
        var steps = [RunWorkoutStep(id: "warmup", kind: .warmup, title: "Warm up", goal: .duration(seconds: edge), target: .init(cue: "Start comfortably"))]
        var remaining = total - edge * 2, index = 0
        while remaining > 0 {
            let isWalk = role == .runWalk && index % 2 == 1
            let isRecovery = role == .quality && index % 2 == 1
            let duration = role == .runWalk ? min(60, remaining) : role == .quality ? min(120, remaining) : remaining
            let cue = isWalk ? "Comfortable walk" : isRecovery ? "Easy recovery" : role == .quality ? "Controlled, not all-out" : "Comfortable conversational effort"
            steps.append(.init(id: "work-\(index)", kind: isWalk || isRecovery ? .recovery : .hard,
                title: isWalk ? "Walk" : isRecovery ? "Recover" : "Run", goal: .duration(seconds: duration), target: .init(cue: cue)))
            remaining -= duration; index += 1
        }
        steps.append(.init(id: "cooldown", kind: .cooldown, title: "Cool down", goal: .duration(seconds: edge), target: .init(cue: "Easy finish")))
        return .init(id: id, name: role.title, subtitle: "\(Int(floor(minutes))) min · effort guided", steps: steps)
    }
}
