import CLockInCore
import SwiftUI

struct NotchRootView: View {
    let viewModel: NotchViewModel
    @State private var isPressed = false

    private var shape: NotchShape {
        NotchShape(topRadius: viewModel.topRadius, bottomRadius: viewModel.bottomRadius)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(.black)
                alertGlow
                content
                    .frame(width: viewModel.bodySize.width, height: viewModel.bodySize.height, alignment: .top)
                    .overlay(alignment: .top) { panel }
            }
            .frame(width: viewModel.shapeSize.width, height: viewModel.shapeSize.height)
            .clipShape(shape)
            .contentShape(shape)
            .gesture(pressGesture, including: viewModel.presentation == .expanded ? .subviews : .all)
            // Pressing squeezes the island toward the bezel, like pressing the Dynamic Island.
            .scaleEffect(isPressed ? 0.96 : 1, anchor: .top)
            .keyframeAnimator(initialValue: 1.0, trigger: viewModel.model.alert?.id) { view, scale in
                view.scaleEffect(scale, anchor: .top)
            } keyframes: { _ in
                SpringKeyframe(1.0, duration: 0.12)
                SpringKeyframe(1.06, duration: 0.22, spring: .bouncy)
                SpringKeyframe(1.0, duration: 0.4, spring: .smooth)
            }
            // Radius 0 when closed: even a transparent shadow is blurred on every frame otherwise.
            .shadow(
                color: .black.opacity(viewModel.presentation == .expanded ? 0.45 : 0),
                radius: viewModel.presentation == .expanded ? 18 : 0,
                y: viewModel.presentation == .expanded ? 8 : 0
            )
            .opacity(viewModel.isShapeVisible ? 1 : 0)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(viewModel.shapeAnimation, value: viewModel.presentation)
        .animation(Motion.hover, value: viewModel.isHovering)
        .animation(Motion.press, value: isPressed)
        .environment(\.colorScheme, .dark)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPressed { isPressed = true }
            }
            .onEnded { value in
                isPressed = false
                if hypot(value.translation.width, value.translation.height) < 12 {
                    viewModel.tapped()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.presentation {
        case .closed:
            Color.clear
        case .compact:
            if let activity = viewModel.model.activity {
                CompactView(activity: activity, notchWidth: viewModel.notchSize.width)
                    .frame(height: viewModel.bodySize.height)
                    .transition(.notchContent)
            }
        case .alert:
            if let alert = viewModel.model.alert {
                AlertView(alert: alert, model: viewModel.model, notchSize: viewModel.notchSize)
                    .transition(.notchContent)
            }
        case .expanded:
            Color.clear
        }
    }

    /// The full panel is built once and kept, hidden, so opening only reveals it. Building it on every
    /// open happened during the first frames of the spring and dropped frames. It scales and fades in
    /// without blur: blurring something this large on every frame was the main cause of stutter.
    private var panel: some View {
        let isShown = viewModel.presentation == .expanded
        let size = NotchViewModel.expandedBodySize(for: viewModel.notchSize)
        return ExpandedView(viewModel: viewModel)
            // Only read the live clock while visible; hidden, the panel gets a fixed date and stays still.
            .environment(\.panelClock, isShown ? viewModel.model.now : viewModel.hiddenPanelClock)
            .frame(width: size.width, height: size.height, alignment: .top)
            .modifier(BloomModifier(blur: 0, scale: isShown ? 1 : 0.86, opacity: isShown ? 1 : 0))
            .animation(isShown ? Motion.contentIn : Motion.contentOut, value: isShown)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
    }

    /// A soft light rising from the bottom edge in the alert's color. It stays inside the shape and away
    /// from the top, so it never traces the hardware notch the way an outline would.
    @ViewBuilder
    private var alertGlow: some View {
        if viewModel.presentation == .alert, let tint = viewModel.model.alert?.tint {
            EllipticalGradient(
                colors: [tint.opacity(0.65), tint.opacity(0.18), .clear],
                center: .bottom,
                startRadiusFraction: 0,
                endRadiusFraction: 0.62
            )
            .phaseAnimator([0.4, 1.0]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 1.2)
            }
            .allowsHitTesting(false)
            .transition(.opacity.animation(.easeInOut(duration: 0.4)))
        }
    }
}

/// Ring and icon to the left of the notch, time to the right.
struct CompactView: View {
    let activity: LiveActivity
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ProgressRing(progress: activity.progress, tint: activity.tint, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
                Image(systemName: activity.isPaused ? "pause.fill" : activity.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(activity.tint)
                    .contentTransition(.symbolEffect(.replace))
                    // A few pulses when the reminder appears, not forever: it can sit there a long time.
                    .symbolEffect(.pulse, options: .repeat(3), value: activity.kind == .finished)
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: notchWidth)

            AnimatedTime(
                text: activity.timeText,
                size: 13,
                color: activity.kind == .finished ? activity.tint : activity.isPaused ? Theme.secondaryText : .white,
                rolls: false
            )
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The "done" state: what finished, plus a follow-up action when there is one.
struct AlertView: View {
    let alert: NotchAlert
    let model: AppModel
    let notchSize: CGSize

    private func actionTitle(_ action: NotchAlert.Action) -> String {
        if case .snooze = action { return "Snooze \(model.settings.snoozeMinutes)m" }
        return action.title
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: alert.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(alert.tint)
                    .symbolEffect(.bounce, options: .repeating.speed(0.6), value: alert.id)
                Spacer(minLength: notchSize.width)
                Text(alert.isAlarm ? "Alarm" : "Done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(alert.tint)
            }
            .padding(.horizontal, 18)
            .frame(height: notchSize.height)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(alert.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if let action = alert.action {
                    Button(actionTitle(action)) { model.performAlertAction() }
                        .buttonStyle(PillButtonStyle(tint: alert.tint, prominent: true))
                }
                Button {
                    model.dismissAlert()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(CircleButtonStyle())
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        }
    }
}
