import SwiftUI
import MyFitPlateCore

/// Compact, persistent diary navigation. Opening a calendar never changes the diary;
/// the reviewed day is applied explicitly and cannot be a future consumption day.
struct DiaryDateNavigator: View {
    let day: DiaryDayContext
    var subtitle: String?
    let onSelect: (DiaryDayContext) -> Void
    @State private var showingCalendar = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    calendarButton
                    HStack(spacing: AppSpacing.compact) {
                        previousButton
                        nextButton
                        Spacer(minLength: 0)
                        if canReturnToToday { todayButton }
                    }
                }
            } else {
                HStack(spacing: AppSpacing.compact) {
                    previousButton
                    calendarButton
                    nextButton
                    if canReturnToToday { todayButton }
                }
            }
        }
        .sheet(isPresented: $showingCalendar) {
            DiaryCalendarSheet(day: day, onSelect: onSelect)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_diary_date_navigation")
    }

    private var canReturnToToday: Bool { !day.isToday() || day.timeZoneIdentifier != TimeZone.current.identifier }

    private var calendarButton: some View {
        Button { showingCalendar = true } label: {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(day.isToday() ? "Today · \(formattedDate(.medium))" : formattedDate(.medium))
                        .appFont(size: 17, weight: .semibold)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("home_date_label")
                    Image(systemName: "chevron.down").appTextRole(.caption).foregroundStyle(.secondary)
                }
                if let subtitle {
                    Text(subtitle).appFont(size: 12, weight: .medium).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose diary date, \(formattedDate(.full))")
        .accessibilityValue(day.isToday() ? "Today" : "Historical day")
        .accessibilityHint("Opens the calendar and jump-to-date controls. Your diary changes only after Show day.")
        .accessibilityIdentifier("home_diary_calendar")
    }

    private var previousButton: some View {
        Button { if let previous = day.adding(days: -1) { onSelect(previous) } } label: {
            Image(systemName: "chevron.left")
        }
        .buttonStyle(AppIconButtonStyle(.neutral))
        .accessibilityLabel("Previous day")
        .accessibilityIdentifier("home_diary_previous")
    }

    private var nextButton: some View {
        Button { if let next = day.adding(days: 1), !next.isFuture() { onSelect(next) } } label: {
            Image(systemName: "chevron.right")
        }
        .buttonStyle(AppIconButtonStyle(.neutral))
        .disabled(day.isToday() || day.isFuture())
        .accessibilityLabel("Next day")
        .accessibilityHint(day.isToday() ? "Future days are for planning, not consumed food." : "Opens the following diary day.")
        .accessibilityIdentifier("home_diary_next")
    }

    private var todayButton: some View {
        Button {
            if let today = DiaryDayContext(userID: day.userID, date: Date(), timeZone: .current) {
                onSelect(today)
            }
        } label: {
            Text("Today").appFont(size: 13, weight: .semibold)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .disabled(day.isToday() && day.timeZoneIdentifier == TimeZone.current.identifier)
        .accessibilityLabel("Return to today's diary")
        .accessibilityIdentifier("home_diary_today")
    }

    private func formattedDate(_ style: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.calendar = day.calendar
        formatter.timeZone = day.timeZone
        formatter.dateStyle = style
        return formatter.string(from: day.displayDate)
    }
}

private struct DiaryCalendarSheet: View {
    let day: DiaryDayContext
    let onSelect: (DiaryDayContext) -> Void
    @State private var pendingDate: Date
    @Environment(\.dismiss) private var dismiss

    init(day: DiaryDayContext, onSelect: @escaping (DiaryDayContext) -> Void) {
        self.day = day
        self.onSelect = onSelect
        _pendingDate = State(initialValue: day.displayDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    Menu("Jump back") {
                        Button("1 week ago") { jump(.day, value: -7) }
                        Button("1 month ago") { jump(.month, value: -1) }
                        Button("3 months ago") { jump(.month, value: -3) }
                        Button("6 months ago") { jump(.month, value: -6) }
                            .accessibilityIdentifier("diary_calendar_jump_6_months")
                        Button("1 year ago") { jump(.year, value: -1) }
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("diary_calendar_jump")

                    DatePicker("Diary date", selection: $pendingDate, in: ...latestDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("diary_calendar_picker")

                    Text("Review or correct food you've already eaten. Plan future meals in the meal planner.")
                        .appFont(size: 13).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppSpacing.screenHorizontal)
            }
            .background(AppPalette.canvas)
            .navigationTitle("Choose diary date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("diary_calendar_cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show day", action: apply)
                        .accessibilityIdentifier("diary_calendar_apply")
                }
            }
        }
        .environment(\.calendar, day.calendar)
        .environment(\.timeZone, day.timeZone)
    }

    private func jump(_ component: Calendar.Component, value: Int) {
        if let date = day.calendar.date(byAdding: component, value: value, to: Date()) { pendingDate = date }
    }

    private var latestDate: Date {
        let today = day.calendar.startOfDay(for: Date())
        return day.calendar.date(byAdding: .day, value: 1, to: today)?.addingTimeInterval(-1) ?? Date()
    }

    private func apply() {
        guard let selection = DiaryDayContext(userID: day.userID,
            date: day.calendar.startOfDay(for: pendingDate), timeZone: day.timeZone), !selection.isFuture() else { return }
        onSelect(selection)
        dismiss()
    }
}
