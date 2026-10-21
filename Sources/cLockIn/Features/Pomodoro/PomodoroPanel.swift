import CLockInCore
import SwiftUI

struct PomodoroPanel: View {
    let viewModel: NotchViewModel
    @State private var isEditing: Bool

    init(viewModel: NotchViewModel, isEditing: Bool = false) {
        self.viewModel = viewModel
        _isEditing = State(initialValue: isEditing)
    }

    private var model: AppModel { viewModel.model }
    private var pomodoro: PomodoroEngine { model.pomodoro }
    private var tint: Color { Theme.tint(for: pomodoro.phase) }

    private enum Mode: Equatable { case overview, typing, editor }

    private var mode: Mode {
        if viewModel.isEditing(.pomodoroDial) { return .typing }
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
            RingDial(progress: pomodoro.progress(at: model.now), tint: tint) {
                DialCenter(
                    time: TimeFormat.clock(pomodoro.remaining(at: model.now)),
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
                Label(pomodoro.phase.title, systemImage: Theme.symbol(for: pomodoro.phase))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))

                HStack(spacing: 8) {
                    RoundDots(
                        completed: pomodoro.completedFocusRounds,
                        total: pomodoro.config.roundsBeforeLongBreak,
                        tint: Theme.focus
                    )
                    Text("\(pomodoro.roundsToday) today")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .contentTransition(.numericText())
                }

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
