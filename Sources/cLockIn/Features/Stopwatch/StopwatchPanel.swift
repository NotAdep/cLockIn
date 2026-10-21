import CLockInCore
import SwiftUI

struct StopwatchPanel: View {
    let model: AppModel
    /// Only redraw every frame while the panel is on screen and the stopwatch is running.
    let isVisible: Bool

    private var stopwatch: StopwatchEngine { model.stopwatch }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !(isVisible && stopwatch.isRunning))) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        StopwatchText(elapsed: stopwatch.elapsed(at: context.date), size: 40)
                        if !stopwatch.laps.isEmpty {
                            HStack(spacing: 4) {
                                Text("Lap \(stopwatch.laps.count + 1)")
                                StopwatchText(elapsed: stopwatch.currentLap(at: context.date), size: 12, weight: .medium)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        stopwatch.toggle()
                    } label: {
                        Label(primaryTitle, systemImage: stopwatch.isRunning ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(PillButtonStyle(tint: Theme.stopwatch, prominent: true))

                    Button {
                        stopwatch.isRunning ? stopwatch.lap() : stopwatch.reset()
                    } label: {
                        Text(stopwatch.isRunning ? "Lap" : "Reset")
                    }
                    .buttonStyle(PillButtonStyle(tint: .white))
                    .disabled(!stopwatch.isActive)
                }
            }
            .frame(width: 210, alignment: .leading)

            LapList(stopwatch: stopwatch)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 4)
    }

    private var primaryTitle: String {
        if stopwatch.isRunning { return "Pause" }
        return stopwatch.isActive ? "Resume" : "Start"
    }
}

/// "1:02.37": minutes, seconds and hundredths, or hours when needed.
struct StopwatchText: View {
    let elapsed: TimeInterval
    var size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Text(Self.format(elapsed))
            .font(.system(size: size, weight: weight, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    static func format(_ elapsed: TimeInterval) -> String {
        let hundredths = Int((elapsed * 100).rounded(.down))
        let hours = hundredths / 360_000
        let minutes = (hundredths / 6000) % 60
        let seconds = (hundredths / 100) % 60
        let fraction = hundredths % 100
        return hours > 0
            ? String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, fraction)
            : String(format: "%d:%02d.%02d", minutes, seconds, fraction)
    }
}

private struct LapList: View {
    let stopwatch: StopwatchEngine

    var body: some View {
        if stopwatch.laps.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.tertiaryText)
                Text("Laps appear here")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let durations = stopwatch.lapDurations
            let extremes = stopwatch.lapExtremes
            // The newest laps that fit. A ScrollView would put an AppKit view inside the animated panel.
            let shown = Array(durations.indices.reversed().prefix(Self.visibleLaps))
            VStack(spacing: 0) {
                    ForEach(shown, id: \.self) { index in
                        HStack {
                            Text("Lap \(index + 1)")
                            Spacer()
                            Text(StopwatchText.format(durations[index])).monospacedDigit()
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(color(for: index, extremes: extremes))
                        .padding(.vertical, 5)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if durations.count > Self.visibleLaps {
                        Text("\(durations.count - Self.visibleLaps) earlier laps")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.top, 4)
                    }
            }
            .animation(Motion.content, value: stopwatch.laps.count)
        }
    }

    private static let visibleLaps = 5

    /// Fastest lap in green and slowest in red, like the Clock app.
    private func color(for index: Int, extremes: (fastest: Int, slowest: Int)?) -> Color {
        guard let extremes else { return .white.opacity(0.85) }
        if index == extremes.fastest { return Theme.shortBreak }
        if index == extremes.slowest { return Theme.focus }
        return .white.opacity(0.85)
    }
}
