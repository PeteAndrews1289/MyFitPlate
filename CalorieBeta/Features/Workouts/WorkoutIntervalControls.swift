import MyFitPlateCore
import SwiftUI

struct WorkoutIntervalControls: View {
    @Binding var set: ExerciseSet
    let isHold: Bool
    var onComplete: (() -> Void)?
    @State private var errorMessage: String?
    private var target: Int? {
        WorkoutDurationEntryRules.intervalTargetSeconds(prescription: set.prescription,
            legacyTarget: set.target, bareNumberIsSeconds: isHold)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let timer = set.intervalTimer {
                    let rawElapsed = timer.elapsed(at: context.date)
                    let elapsed = Int(timer.completedAt == nil ? rawElapsed : rawElapsed.rounded())
                    let status = timer.completedAt != nil ? "Completed" : timer.runningSince == nil ? "Paused" : "Running"
                    Text("\(elapsed / 60):\(String(format: "%02d", elapsed % 60)) active · \(status)")
                        .appTextRole(.control).monospacedDigit()
                        .accessibilityLabel("\(elapsed) active seconds, \(status.lowercased())")
                    if let target = timer.targetSeconds {
                        Text(timer.completedAt != nil ? "Target \(target) sec · measured \(elapsed) sec"
                             : elapsed >= target ? "Target reached · complete when ready" : "\(target - elapsed) seconds to target")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !set.isCompleted {
                ViewThatFits(in: .horizontal) {
                    HStack { actions }
                    VStack(alignment: .leading) { actions }
                }
                Text("Tracks this \(isHold ? "hold" : "interval") only. Pause before manual correction; your recovery timer is separate. A recovered clock keeps its elapsed segments and never completes a set automatically.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("interval_controls_\(set.id)")
    }
    @ViewBuilder private var actions: some View {
        if set.intervalTimer?.runningSince != nil {
            Button("Pause") {
                do { var timer = try current(); try timer.pause(); set.intervalTimer = timer; errorMessage = nil } catch { errorMessage = error.localizedDescription }
            }.frame(minHeight: 44).buttonStyle(AppListButtonStyle()).accessibilityIdentifier("interval_pause_\(set.id)")
        } else {
            Button(set.intervalTimer == nil ? "Start \(isHold ? "hold" : "interval")" : "Resume") {
                do { var timer = try current(); try timer.start(); set.intervalTimer = timer; errorMessage = nil } catch { errorMessage = error.localizedDescription }
            }.frame(minHeight: 44).buttonStyle(AppListButtonStyle()).accessibilityIdentifier("interval_start_\(set.id)")
        }
        if set.intervalTimer != nil {
            Button("Complete measured set") {
                do {
                    var timer = try current(); let seconds = try timer.complete()
                    set.durationInSeconds = seconds; set.intervalTimer = timer; set.isCompleted = true
                    errorMessage = nil; onComplete?()
                } catch { errorMessage = "Start and record at least one second before completing." }
            }.frame(minHeight: 44).buttonStyle(AppListButtonStyle()).accessibilityIdentifier("interval_complete_\(set.id)")
        }
    }
    private func current() throws -> WorkoutIntervalTimerState {
        let value = set.intervalTimer ?? WorkoutIntervalTimerState(setID: set.id, targetSeconds: target)
        guard value.isValid, value.setID == set.id else { throw WorkoutBlockError.invalid }
        return value
    }
}
