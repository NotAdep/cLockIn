import CLockInCore
import SwiftUI

struct PomodoroPanel: View {
    let viewModel: NotchViewModel
    @Environment(\.panelClock) private var now
    @State private var isEditing: Bool
    @State private var isPickingLabel = false

    init(viewModel: NotchViewModel, isEditing: Bool = false) {
        self.viewModel = viewModel
        _isEditing = State(initialValue: isEditing)
    }

    private var model: AppModel { viewModel.model }
    private var pomodoro: PomodoroEngine { model.pomodoro }
    private var tint: Color { Theme.tint(for: pomodoro.phase) }

    private enum Mode: Equatable { case overview, typing, editor, labels }

    private var mode: Mode {
        if viewModel.isEditing(.pomodoroDial) { return .typing }
        if isPickingLabel { return .labels }
        return isEditing ? .editor : .overview
    }

    var body: some View {
        HStack(spacing: 26) {
            dial
                .frame(width: 128, height: 128)

            Group {
                switch mode {
                case .overview: overview
                case .typing: DurationTypingControls(title: "Custom \(pomodoro.phase.title.lowercased())", tint: tint, viewModel: viewModel)
                case .editor: editor
                case .labels: LabelPicker(model: model) { isPickingLabel = false }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 8)).animation(Motion.content.delay(0.05)),
                removal: .opacity.animation(.easeOut(duration: 0.12))
            ))
            .id(mode)
        }
        .animation(Motion.content, value: pomodoro.phase)
        .animation(Motion.content, value: mode)
    }

    // MARK: Dial

    @ViewBuilder
    private var dial: some View {
        if pomodoro.isActive {
            RingDial(progress: pomodoro.progress(at: now), tint: tint) {
                DialCenter(
                    time: TimeFormat.clock(pomodoro.remaining(at: now)),
                    caption: pomodoro.isPaused ? "Paused" : pomodoro.phase.title,
                    tint: tint,
                    dimmed: pomodoro.isPaused
                )
            }
        } else if viewModel.isEditing(.pomodoroDial) {
            RingDial(progress: 0, tint: tint, highlighted: true) {
                VStack(spacing: 2) {
                    DigitEntryText(entry: viewModel.durationEntry ?? DurationDigits(), tint: tint)
                    Text("Type it")
                        .font(.system(size: 9.5, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(tint.opacity(0.9))
                }
            }
        } else {
            Button {
                viewModel.beginDurationEntry(for: .pomodoroDial)
            } label: {
                RingDial(progress: 0, tint: tint) {
                    DialCenter(
                        time: TimeFormat.clock(pomodoro.config.duration(for: pomodoro.phase)),
                        caption: "Click to type",
                        tint: tint
                    )
                }
            }
            .buttonStyle(DialButtonStyle())
            .help("Click to type a custom \(pomodoro.phase.title.lowercased()) length")
        }
    }

    // MARK: Modes

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label(pomodoro.phase.title, systemImage: Theme.symbol(for: pomodoro.phase))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                    Button { isPickingLabel = true } label: {
                        Label(pomodoro.label ?? "Label", systemImage: pomodoro.label == nil ? "plus" : "tag.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(pomodoro.label == nil ? Theme.secondaryText : .white)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("What this focus is for")
                }

                FocusSummaryRow(model: model, now: now)

                Text("Next: \(pomodoro.nextPhase.title), \(TimeFormat.short(pomodoro.config.duration(for: pomodoro.nextPhase)))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            HStack(spacing: 8) {
                Button {
                    pomodoro.toggle()
                } label: {
                    Label(primaryTitle, systemImage: pomodoro.isRunning ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PillButtonStyle(tint: tint, prominent: true))

                Button { pomodoro.skip() } label: { Image(systemName: "forward.end.fill") }
                    .buttonStyle(CircleButtonStyle())
                    .help("Skip to \(pomodoro.nextPhase.title.lowercased())")

                Button { pomodoro.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(CircleButtonStyle())
                    .help("Reset cycle")

                Button { isEditing = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(CircleButtonStyle())
                    .help("Change durations")

                Button {
                    viewModel.collapse()
                    FocusStatsWindowController.shared.show(model: model)
                } label: { Image(systemName: "chart.bar.xaxis") }
                    .buttonStyle(CircleButtonStyle())
                    .help("Focus statistics")
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(PomodoroPhase.allCases, id: \.self) { phase in
                DurationRow(phase: phase, viewModel: viewModel)
            }
            HStack(spacing: 8) {
                PillToggle(title: "Auto-start next", isOn: autoAdvance, tint: tint)
                Spacer()
                Button("Done") {
                    viewModel.commitDurationEntry(start: false)
                    isEditing = false
                }
                .buttonStyle(PillButtonStyle(tint: tint, prominent: true, compact: true))
            }
            .padding(.top, 2)
        }
    }

    private var primaryTitle: String {
        if pomodoro.isRunning { return "Pause" }
        if pomodoro.isPaused { return "Resume" }
        return pomodoro.phase == .focus ? "Start focus" : "Start break"
    }

    private var autoAdvance: Binding<Bool> {
        Binding(
            get: { pomodoro.config.autoAdvance },
            set: { newValue in
                var config = pomodoro.config
                config.autoAdvance = newValue
                pomodoro.updateConfig(config)
            }
        )
    }
}

/// "Focus   −  25m  +". Click the value to type an exact length, or scroll over it.
private struct DurationRow: View {
    let phase: PomodoroPhase
    let viewModel: NotchViewModel

    private var pomodoro: PomodoroEngine { viewModel.model.pomodoro }
    private var tint: Color { Theme.tint(for: phase) }
    private var value: TimeInterval { pomodoro.config.duration(for: phase) }
    private var isTyping: Bool { viewModel.isEditing(.pomodoroSetting(phase)) }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(phase.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Button { step(-1) } label: { Image(systemName: "minus") }
                .buttonStyle(CircleButtonStyle(size: 22))
                .disabled(value <= 60)
            Button {
                isTyping ? viewModel.commitDurationEntry(start: false) : viewModel.beginDurationEntry(for: .pomodoroSetting(phase))
            } label: {
                Group {
                    if isTyping {
                        DigitEntryText(entry: viewModel.durationEntry ?? DurationDigits(), size: 12, tint: tint)
                    } else {
                        AnimatedTime(text: TimeFormat.short(value), size: 12)
                    }
                }
                .frame(width: 74, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isTyping ? tint.opacity(0.16) : .clear)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(tint.opacity(isTyping ? 0.6 : 0), lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .scrollTarget(.pomodoroSetting(phase), in: viewModel)
            .help("Click to type an exact length")
            .animation(Motion.content, value: isTyping)
            Button { step(1) } label: { Image(systemName: "plus") }
                .buttonStyle(CircleButtonStyle(size: 22))
                .disabled(value >= TimerEngine.durationRange.upperBound)
        }
        .frame(height: 24)
    }

    private func step(_ direction: Int) {
        viewModel.stepPomodoroDuration(for: phase, by: direction)
    }
}

/// Rounds in this cycle, today's focus time, the streak and a tiny bar for each of the last seven days.
private struct FocusSummaryRow: View {
    let model: AppModel
    let now: Date

    var body: some View {
        let history = model.history
        let week = history.days(7, endingAt: now)
        let today = week.last?.focused ?? 0
        let streak = history.streak(at: now)
        HStack(spacing: 8) {
            RoundDots(
                completed: model.pomodoro.completedFocusRounds,
                total: model.pomodoro.config.roundsBeforeLongBreak,
                tint: Theme.focus
            )
            Text(today > 0 ? "\(TimeFormat.short(today)) today" : "\(model.pomodoro.roundsToday) today")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .contentTransition(.numericText())
            if streak > 1 {
                Label("\(streak)", systemImage: "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.timer)
                    .help("\(streak)-day streak")
            }
            WeekBars(days: week)
                .frame(width: 44, height: 14)
                .help("Focus time, last 7 days")
        }
    }
}

/// Seven tiny bars, today on the right.
private struct WeekBars: View {
    let days: [FocusDay]

    var body: some View {
        let peak = max(days.map(\.focused).max() ?? 0, 60)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(days.indices, id: \.self) { index in
                let value = days[index].focused
                RoundedRectangle(cornerRadius: 1)
                    .fill(index == days.count - 1 ? Theme.focus : Color.white.opacity(value > 0 ? 0.5 : 0.15))
                    .frame(height: max(2, 14 * value / peak))
            }
        }
    }
}

/// Pick what the current focus rounds are for. New labels are made in the statistics window.
private struct LabelPicker: View {
    let model: AppModel
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Label this focus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                chip(nil, title: "None")
                ForEach(model.history.labels.prefix(9), id: \.self) { label in
                    chip(label, title: label)
                }
            }
            HStack {
                Button("New label…") {
                    done()
                    FocusStatsWindowController.shared.show(model: model, editingLabels: true)
                }
                .buttonStyle(PillButtonStyle(tint: .white, compact: true))
                Spacer()
                Button("Done", action: done)
                    .buttonStyle(PillButtonStyle(tint: Theme.focus, prominent: true, compact: true))
            }
        }
    }

    private func chip(_ label: String?, title: String) -> some View {
        let selected = model.pomodoro.label == label
        return Button {
            model.pomodoro.setLabel(label)
            done()
        } label: {
            Text(title)
                .lineLimit(1)
        }
        .buttonStyle(PillButtonStyle(tint: selected ? Theme.focus : .white, compact: true))
    }
}

private struct RoundDots: View {
    let completed: Int
    let total: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed ? tint : Color.white.opacity(0.18))
                    .frame(width: 7, height: 7)
                    .scaleEffect(index < completed ? 1 : 0.85)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: completed)
    }
}
