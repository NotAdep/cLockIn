import CLockInCore
import SwiftUI

struct AlarmsPanel: View {
    let viewModel: NotchViewModel

    private var alarms: AlarmEngine { viewModel.model.alarms }

    var body: some View {
        ZStack {
            if let draft = viewModel.alarmDraft {
                AlarmEditor(viewModel: viewModel, draft: draft)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            } else {
                list
                    .transition(.opacity)
            }
        }
        .animation(Motion.content, value: viewModel.alarmDraft != nil)
    }

    private static let visibleAlarms = 3

    @ViewBuilder
    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let next = alarms.nextAlarm {
                    Label("Next in \(relative(next.date))", systemImage: "alarm.fill")
                        .foregroundStyle(Theme.alarm)
                } else {
                    Label("No alarms on", systemImage: "alarm")
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                SnoozeControl(viewModel: viewModel)
                Button {
                    viewModel.beginNewAlarm()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(CircleButtonStyle(size: 24))
                .help("Add alarm")
            }
            .font(.system(size: 11, weight: .medium))

            if alarms.alarms.isEmpty {
                Button {
                    viewModel.beginNewAlarm()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "alarm")
                            .font(.system(size: 22))
                        Text("Add an alarm")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(alarms.alarms.prefix(Self.visibleAlarms)) { alarm in
                        AlarmRow(alarm: alarm, viewModel: viewModel)
                    }
                }
                if alarms.alarms.count > Self.visibleAlarms {
                    Text("\(alarms.alarms.count - Self.visibleAlarms) more in the menu bar")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let minutes = Int(ceil(date.timeIntervalSince(viewModel.model.now) / 60))
        if minutes < 60 { return "\(max(1, minutes))m" }
        let hours = minutes / 60
        return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
    }
}

/// "Snooze − 9m +" in the list header; scroll over the number to change it too.
private struct SnoozeControl: View {
    let viewModel: NotchViewModel

    private var minutes: Int { viewModel.model.settings.snoozeMinutes }

    var body: some View {
        HStack(spacing: 4) {
            Text("Snooze")
                .foregroundStyle(Theme.secondaryText)
            Button { viewModel.model.setSnoozeMinutes(minutes - 1) } label: { Image(systemName: "minus") }
                .buttonStyle(CircleButtonStyle(size: 20))
                .disabled(minutes <= 1)
            AnimatedTime(text: "\(minutes)m", size: 11, weight: .semibold)
                .frame(width: 28)
                .scrollTarget(.snoozeLength, in: viewModel)
            Button { viewModel.model.setSnoozeMinutes(minutes + 1) } label: { Image(systemName: "plus") }
                .buttonStyle(CircleButtonStyle(size: 20))
                .disabled(minutes >= 60)
        }
        .padding(.trailing, 6)
        .help("How long Snooze waits before ringing again")
    }
}

private struct AlarmRow: View {
    let alarm: Alarm
    let viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.edit(alarm)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(AlarmTimeText.format(hour: alarm.hour, minute: alarm.minute))
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(alarm.isEnabled ? 1 : 0.4))
                    Text("\(alarm.label) · \(alarm.repeatSummary())")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit alarm")

            PillToggle(
                title: "",
                isOn: Binding(
                    get: { alarm.isEnabled },
                    set: { viewModel.model.alarms.setEnabled($0, for: alarm.id) }
                ),
                tint: Theme.alarm
            )
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
        .animation(Motion.content, value: alarm.isEnabled)
    }
}

/// Add or edit one alarm: time (scroll, ± or type it), repeat days, then Save.
private struct AlarmEditor: View {
    let viewModel: NotchViewModel
    let draft: Alarm

    private var isTyping: Bool { viewModel.isEditing(.alarmTime) }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 8) {
                timeField
                HStack(spacing: 6) {
                    stepButtons(label: "hour", hours: 1)
                    stepButtons(label: "min", minutes: 5)
                }
                Text(isTyping ? "Type HHMM, then Return" : "Scroll, use ±, or click to type")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(width: 190)

            VStack(alignment: .leading, spacing: 12) {
                Text("Repeat")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                DayPicker(days: Binding(
                    get: { viewModel.alarmDraft?.repeatDays ?? [] },
                    set: { viewModel.alarmDraft?.repeatDays = $0 }
                ))
                Text(draft.repeatSummary())
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)

                HStack(spacing: 8) {
                    Button("Save") { viewModel.saveAlarmDraft() }
                        .buttonStyle(PillButtonStyle(tint: Theme.alarm, prominent: true))
                    Button("Cancel") { viewModel.cancelAlarmDraft() }
                        .buttonStyle(PillButtonStyle(tint: .white))
                    if !viewModel.isNewAlarm {
                        Button { viewModel.deleteAlarmDraft() } label: { Image(systemName: "trash") }
                            .buttonStyle(CircleButtonStyle())
                            .help("Delete alarm")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var timeField: some View {
        Button {
            isTyping ? viewModel.commitDurationEntry(start: false) : viewModel.beginDurationEntry(for: .alarmTime)
        } label: {
            Group {
                if isTyping {
                    DigitEntryText(entry: viewModel.durationEntry ?? DurationDigits(), size: 34, tint: Theme.alarm, fields: 2)
                } else {
                    HStack(spacing: 0) {
                        Text(String(format: NotchViewModel.uses12HourClock ? "%d" : "%02d", AlarmTimeText.displayHour(draft.hour)))
                            .scrollTarget(.alarmHour, in: viewModel)
                        Text(":")
                        Text(String(format: "%02d", draft.minute))
                            .scrollTarget(.alarmMinute, in: viewModel)
                        if let period = AlarmTimeText.period(draft.hour) {
                            Text(" " + period).font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(isTyping ? Theme.alarm.opacity(0.14) : Color.white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.digits, value: draft)
    }

    private func stepButtons(label: String, hours: Int = 0, minutes: Int = 0) -> some View {
        HStack(spacing: 4) {
            Button { viewModel.stepAlarm(hours: -hours, minutes: -minutes) } label: { Image(systemName: "minus") }
                .buttonStyle(CircleButtonStyle(size: 22))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 28)
            Button { viewModel.stepAlarm(hours: hours, minutes: minutes) } label: { Image(systemName: "plus") }
                .buttonStyle(CircleButtonStyle(size: 22))
        }
    }
}

/// Seven round day toggles in the order this region starts its week.
private struct DayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 5) {
            ForEach(order, id: \.self) { weekday in
                let isOn = days.contains(weekday)
                Button {
                    if isOn { days.remove(weekday) } else { days.insert(weekday) }
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOn ? Color.black : .white.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(isOn ? Theme.alarm : Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .animation(Motion.press, value: isOn)
            }
        }
    }
}

enum AlarmTimeText {
    static func displayHour(_ hour: Int) -> Int {
        guard NotchViewModel.uses12HourClock else { return hour }
        return hour % 12 == 0 ? 12 : hour % 12
    }

    static func period(_ hour: Int) -> String? {
        guard NotchViewModel.uses12HourClock else { return nil }
        return hour < 12 ? Calendar.current.amSymbol : Calendar.current.pmSymbol
    }

    static func format(hour: Int, minute: Int) -> String {
        let base = String(format: NotchViewModel.uses12HourClock ? "%d:%02d" : "%02d:%02d", displayHour(hour), minute)
        return period(hour).map { "\(base) \($0)" } ?? base
    }
}
