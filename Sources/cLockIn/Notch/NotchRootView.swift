import CLockInCore
import SwiftUI

struct NotchRootView: View {
    let viewModel: NotchViewModel
    @Namespace private var namespace
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
            .shadow(color: .black.opacity(viewModel.presentation == .expanded ? 0.45 : 0), radius: 18, y: 8)
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
                CompactView(activity: activity, notchWidth: viewModel.notchSize.width, namespace: namespace)
                    .frame(height: viewModel.bodySize.height)
                    .transition(.notchContent)
            }
        case .alert:
            if let alert = viewModel.model.alert {
                AlertView(alert: alert, model: viewModel.model, notchSize: viewModel.notchSize)
                    .transition(.notchContent)
            }
        case .expanded:
            ExpandedView(viewModel: viewModel, namespace: namespace)
                .transition(.notchContent)
        }
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
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ProgressRing(progress: activity.progress, tint: activity.tint, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
                    .matchedGeometryEffect(id: ringID, in: namespace)
                Image(systemName: activity.isPaused ? "pause.fill" : activity.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(activity.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: notchWidth)

            AnimatedTime(
                text: TimeFormat.clock(activity.remaining),
                size: 13,
                color: activity.isPaused ? Theme.secondaryText : .white
            )
            .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var ringID: String { "ring-\(activity.kind)" }
}

/// The "done" state: what finished, plus a follow-up action when there is one.
struct AlertView: View {
    let alert: NotchAlert
    let model: AppModel
    let notchSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: alert.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(alert.tint)
                    .symbolEffect(.bounce, options: .repeating.speed(0.6), value: alert.id)
                Spacer(minLength: notchSize.width)
                Text("Done")
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
                if alert.action != nil {
                    Button("Start") { model.performAlertAction() }
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
