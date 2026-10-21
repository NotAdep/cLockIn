import AppKit
import CLockInCore
import SwiftUI

enum Theme {
    static let timer = Color(red: 1.0, green: 0.62, blue: 0.2)
    static let focus = Color(red: 1.0, green: 0.36, blue: 0.33)
    static let shortBreak = Color(red: 0.3, green: 0.85, blue: 0.5)
    static let longBreak = Color(red: 0.3, green: 0.75, blue: 0.95)
    static let stopwatch = Color(red: 0.35, green: 0.8, blue: 1.0)
    static let worldClock = Color(red: 0.75, green: 0.6, blue: 1.0)
    /// Pink, so alarms never read as the orange timer.
    static let alarm = Color(red: 0.98, green: 0.45, blue: 0.78)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.3)
    static let control = Color.white.opacity(0.1)

    static func tint(for phase: PomodoroPhase) -> Color {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }

    static func symbol(for phase: PomodoroPhase) -> String {
        switch phase {
        case .focus: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        }
    }
}

enum Motion {
    /// Snappy, slightly bouncy, like the Dynamic Island opening.
    static let open = Animation.spring(response: 0.5, dampingFraction: 0.72)
    static let compact = Animation.spring(response: 0.45, dampingFraction: 0.8)
    /// Closing uses the same lively spring as opening, just a touch quicker.
    static let close = Animation.spring(response: 0.45, dampingFraction: 0.74)
    static let hover = Animation.spring(response: 0.3, dampingFraction: 0.62)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.6)
    static let content = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let digits = Animation.snappy(duration: 0.35)
    /// Panel content arriving just after the shape starts to grow, and leaving before it shrinks.
    static let contentIn = Animation.spring(response: 0.42, dampingFraction: 0.86).delay(0.07)
    static let contentOut = Animation.spring(response: 0.26, dampingFraction: 0.9)
}

extension AnyTransition {
    /// Content blooms out of the notch after the shape starts growing, and is drawn back in as it shrinks.
    static var notchContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BloomModifier(blur: 10, scale: 0.86, opacity: 0),
                identity: BloomModifier(blur: 0, scale: 1, opacity: 1)
            ).animation(Motion.contentIn),
            removal: .modifier(
                active: BloomModifier(blur: 8, scale: 0.88, opacity: 0),
                identity: BloomModifier(blur: 0, scale: 1, opacity: 1)
            ).animation(Motion.contentOut)
        )
    }
}

struct BloomModifier: ViewModifier {
    var blur: CGFloat
    var scale: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .top)
            .opacity(opacity)
    }
}

/// Clock digits that roll as they change.
struct AnimatedTime: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .contentTransition(.numericText(countsDown: true))
            .animation(Motion.digits, value: text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// A circular progress track that fills clockwise from the top.
struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

/// The large ring used in the expanded panel; its center is supplied by the caller.
struct RingDial<Center: View>: View {
    var progress: Double
    var tint: Color
    var highlighted = false
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            ProgressRing(progress: progress, tint: tint, lineWidth: 7)
            if highlighted {
                Circle()
                    .stroke(tint.opacity(0.6), lineWidth: 1)
                    .padding(10)
                    .phaseAnimator([0.3, 1]) { view, opacity in view.opacity(opacity) }
                        animation: { _ in .easeInOut(duration: 0.8) }
                    .transition(.opacity)
            }
            center.padding(16)
        }
        .animation(Motion.content, value: highlighted)
    }
}

struct DialCenter: View {
    var time: String
    var caption: String
    var tint: Color
    var dimmed = false

    var body: some View {
        VStack(spacing: 2) {
            AnimatedTime(text: time, size: 26, color: .white.opacity(dimmed ? 0.5 : 1))
            Text(caption)
                .font(.system(size: 9.5, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(tint.opacity(0.9))
                .contentTransition(.opacity)
                .lineLimit(1)
        }
    }
}

/// HH:MM:SS where the typed digits are bright and the zero padding is dim, with a blinking caret.
struct DigitEntryText: View {
    let entry: DurationDigits
    var size: CGFloat = 21
    var tint: Color = Theme.timer
    /// 3 shows HH:MM:SS; 2 shows HH:MM (the last four digits).
    var fields = 3

    var body: some View {
        let count = fields * 2
        let padded = Array(entry.padded.suffix(count))
        let typedFrom = count - min(entry.digits.count, count)
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                if index > 0 && index % 2 == 0 {
                    Text(":").foregroundStyle(index >= typedFrom ? Color.white : Theme.tertiaryText)
                }
                Text(String(padded[index]))
                    .foregroundStyle(index >= typedFrom ? Color.white : Theme.tertiaryText)
                    .contentTransition(.numericText())
            }
            Rectangle()
                .fill(tint)
                .frame(width: 2, height: size * 0.95)
                .padding(.leading, 2)
                .phaseAnimator([1.0, 0.0]) { view, opacity in view.opacity(opacity) }
                    animation: { _ in .easeInOut(duration: 0.5) }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
        .animation(Motion.digits, value: entry)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

// MARK: Buttons

struct PillButtonStyle: ButtonStyle {
    var tint: Color
    var prominent = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, tint: tint, prominent: prominent, compact: compact)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let tint: Color
        let prominent: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, compact ? 9 : 12)
                .frame(height: 28)
                .foregroundStyle(prominent ? Color.black : tint)
                .background(Capsule().fill(prominent ? tint : tint.opacity(hovering ? 0.26 : 0.16)))
                .brightness(prominent && hovering ? 0.08 : 0)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.93 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

struct CircleButtonStyle: ButtonStyle {
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        CircleBody(configuration: configuration, size: size)
    }

    private struct CircleBody: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.24 : hovering ? 0.17 : 0.1)))
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .contentShape(Circle())
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// Marks this view as a scroll target; the notch controller routes scrolling over it to the view model.
    func scrollTarget(_ target: ScrollTarget, in viewModel: NotchViewModel) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            viewModel.scrollRegions[target] = frame
        }
        .onDisappear { viewModel.scrollRegions[target] = nil }
    }
}

/// A SwiftUI-drawn switch, so nothing in the panel is an AppKit control.
struct PillToggle: View {
    let title: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Capsule()
                    .fill(isOn ? tint : Color.white.opacity(0.2))
                    .frame(width: 26, height: 15)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .padding(2)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    }
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            .contentShape(Rectangle())
            .animation(Motion.press, value: isOn)
        }
        .buttonStyle(.plain)
    }
}
