import CLockInCore
import SwiftUI

struct TimerPanel: View {
    let viewModel: NotchViewModel
    @Environment(\.panelClock) private var now

    private var model: AppModel { viewModel.model }
    private var timer: TimerEngine { model.timer }

    private enum Mode: Equatable { case setup, typing, active }

    private var mode: Mode {
        if viewModel.isEditing(.timer) { return .typing }
        return viewModel.shownTimer == nil ? .setup : .active
    }

    var body: some View {
        HStack(spacing: 26) {
            dial
                .frame(width: 128, height: 128)

            Group {
                switch mode {
                case .setup: setupControls
                case .typing: DurationTypingControls(title: "Custom timer", tint: Theme.timer, viewModel: viewModel)
                case .active: activeControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 8)).animation(Motion.content.delay(0.05)),
                removal: .opacity.animation(.easeOut(duration: 0.12))
            ))
            .id(mode)
        }
        .animation(Motion.content, value: mode)
    }

    // MARK: Dial

    @ViewBuilder
    private var dial: some View {
        switch mode {
        case .active:
            if let shown = viewModel.shownTimer {
                RingDial(progress: shown.countdown.progress(at: now), tint: Theme.timer) {
                    DialCenter(
                        time: TimeFormat.clock(shown.countdown.remaining(at: now)),
                        caption: shown.countdown.isPaused ? "Paused" : "\(shown.label) timer",
                        tint: Theme.timer,
                        dimmed: shown.countdown.isPaused
                    )
                }
                .id(shown.id)
                .transition(.opacity)
            }
        case .typing:
            RingDial(progress: 0, tint: Theme.timer, highlighted: true) {
                VStack(spacing: 2) {
                    DigitEntryText(entry: viewModel.durationEntry ?? DurationDigits())
                    Text("Type it")
                        .font(.system(size: 9.5, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(Theme.timer.opacity(0.9))
                }
            }
        case .setup:
            Button {
                viewModel.beginDurationEntry()
            } label: {
                RingDial(progress: 0, tint: Theme.timer) {
                    DialCenter(time: TimeFormat.clock(timer.selectedDuration), caption: "Click to type", tint: Theme.timer)
                }
            }
            .buttonStyle(DialButtonStyle())
            .scrollTarget(.timerDuration, in: viewModel)
            .help("Click to type a duration, or scroll to change it")
        }
    }

    // MARK: Modes

    @ViewBuilder
    private var setupControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { timer.adjustDuration(by: -60) } label: { Image(systemName: "minus") }
                    .buttonStyle(CircleButtonStyle())
                Button {
                    viewModel.beginDurationEntry()
                } label: {
                    AnimatedTime(text: TimeFormat.short(timer.selectedDuration), size: 18)
                        .frame(minWidth: 76)
                }
                .buttonStyle(.plain)
                .help("Type a custom duration")
                Button { timer.adjustDuration(by: 60) } label: { Image(systemName: "plus") }
                    .buttonStyle(CircleButtonStyle())
            }

            HStack(spacing: 6) {
                ForEach(TimerEngine.presets, id: \.self) { preset in
                    chip(preset)
                }
            }

            HStack(spacing: 6) {
                if timer.isActive {
                    Button { viewModel.stopAddingTimer() } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(CircleButtonStyle())
                        .help("Back to running timers")
                }
                Button {
                    viewModel.startNewTimer()
                } label: {
                    Label(timer.isActive ? "Add" : "Start", systemImage: "play.fill")
                }
                .buttonStyle(PillButtonStyle(tint: Theme.timer, prominent: true))
                .disabled(!timer.canStartAnother)

                ForEach(timer.recentDurations, id: \.self) { recent in
                    chip(recent, symbol: "clock.arrow.circlepath")
                        .contextMenu {
                            Button("Remove from Recents") { timer.removeRecent(recent) }
                        }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Motion.content, value: timer.recentDurations)
        }
    }

    @ViewBuilder
    private var activeControls: some View {
        if let shown = viewModel.shownTimer {
            let paused = shown.countdown.isPaused
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(paused ? "Paused" : "Running")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Group {
                        if let end = shown.countdown.endDate {
                            Text("Ends at \(end.formatted(date: .omitted, time: .shortened))")
                        } else {
                            Text("\(shown.label) timer")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .contentTransition(.numericText())
                }

                HStack(spacing: 8) {
                    Button {
                        timer.toggle(id: shown.id)
                    } label: {
                        Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(PillButtonStyle(tint: Theme.timer, prominent: true))

                    Button("+1 min") { timer.addMinute(id: shown.id) }
                        .buttonStyle(PillButtonStyle(tint: Theme.timer))

                    Button { timer.cancel(id: shown.id) } label: { Image(systemName: "xmark") }
                        .buttonStyle(CircleButtonStyle())
                        .help("Cancel this timer")
                }

                TimerStrip(viewModel: viewModel, selected: shown.id, now: now)
            }
        }
    }

    private func chip(_ duration: TimeInterval, symbol: String? = nil) -> some View {
        Button {
            timer.setDuration(duration)
        } label: {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
                Text(TimeFormat.short(duration))
            }
        }
        .buttonStyle(PillButtonStyle(tint: duration == timer.selectedDuration ? Theme.timer : .white, compact: true))
    }
}

/// Every running timer as a small chip, plus "+" to add another.
private struct TimerStrip: View {
    let viewModel: NotchViewModel
    let selected: UUID
    let now: Date

    private var timer: TimerEngine { viewModel.model.timer }

    var body: some View {
        HStack(spacing: 6) {
            if timer.timers.count > 1 {
                ForEach(timer.sorted(at: now)) { item in
                    Button {
                        viewModel.selectTimer(item.id)
                    } label: {
                        HStack(spacing: 5) {
                            ProgressRing(progress: item.countdown.progress(at: now), tint: Theme.timer, lineWidth: 2)
                                .frame(width: 11, height: 11)
                            Text(TimeFormat.clock(item.countdown.remaining(at: now)))
                                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white.opacity(item.countdown.isPaused ? 0.5 : 0.9))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(item.id == selected ? 0.18 : 0.07)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            if timer.canStartAnother {
                Button { viewModel.beginAddingTimer() } label: {
                    Label(timer.timers.count > 1 ? "" : "Another timer", systemImage: "plus")
                        .labelStyle(AdaptiveLabelStyle(showsTitle: timer.timers.count <= 1))
                }
                .buttonStyle(PillButtonStyle(tint: .white, compact: true))
                .help("Start another timer")
            }
        }
        .animation(Motion.content, value: timer.timers.map(\.id))
    }
}

/// Icon only, or icon and title, without changing the label's identity.
private struct AdaptiveLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            if showsTitle { configuration.title }
        }
    }
}

/// The hint and Start / Cancel buttons shown beside a dial while a duration is being typed.
struct DurationTypingControls: View {
    let title: String
    let tint: Color
    let viewModel: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Type hours, minutes and seconds. 130 is 1:30, 10000 is 1 hour.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    viewModel.commitDurationEntry(start: true)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(PillButtonStyle(tint: tint, prominent: true))
                .disabled(viewModel.durationEntry?.isEmpty ?? true)

                Button("Cancel") { viewModel.cancelDurationEntry() }
                    .buttonStyle(PillButtonStyle(tint: .white))

                KeyHint(keys: ["return"], label: "start")
                KeyHint(keys: ["esc"], label: "cancel")
            }
        }
    }
}

struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .frame(height: 15)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(Theme.tertiaryText))
            }
            Text(label).font(.system(size: 10))
        }
        .foregroundStyle(Theme.secondaryText)
    }
}

/// The idle dial is a button: it brightens on hover and dips when pressed.
struct DialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DialBody(configuration: configuration)
    }

    private struct DialBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .brightness(hovering ? 0.08 : 0)
                .scaleEffect(configuration.isPressed ? 0.95 : hovering ? 1.02 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(Motion.hover, value: hovering)
                .contentShape(Circle())
                .onHover { hovering = $0 }
        }
    }
}
