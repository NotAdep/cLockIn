import SwiftUI

/// The full panel: tabs and settings beside the notch, the selected feature below it.
struct ExpandedView: View {
    let viewModel: NotchViewModel

    private var isShown: Bool { viewModel.presentation == .expanded }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabSwitcher(viewModel: viewModel)
                Spacer(minLength: viewModel.notchSize.width + 12)
                // The World Clock style toggle takes the title's place; both don't fit beside the notch.
                if let app = viewModel.activeAppTab, let panel = viewModel.model.island.panels[app] {
                    Text(panel.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .padding(.trailing, 8)
                } else if viewModel.tab == .worldClock {
                    WorldClockStyleToggle(settings: viewModel.model.settings)
                        .padding(.trailing, 8)
                        .transition(.opacity)
                } else {
                    Text(viewModel.tab.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .contentTransition(.opacity)
                        .lineLimit(1)
                        .padding(.trailing, 8)
                }
                Button {
                    viewModel.collapse()
                    SettingsWindowController.shared.show(model: viewModel.model)
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(CircleButtonStyle(size: 24))
                .overlay(alignment: .topTrailing) {
                    // A small dot when an update is waiting, like a badge on System Settings.
                    if viewModel.model.updates.availableUpdate != nil {
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7).offset(x: 1, y: -1)
                    }
                }
                .help(viewModel.model.updates.availableUpdate == nil ? "Settings" : "Settings (update available)")
            }
            .padding(.horizontal, 16)
            .frame(height: viewModel.notchSize.height)

            ZStack {
                if let app = viewModel.activeAppTab, let panel = viewModel.model.island.panels[app],
                   let client = viewModel.model.island.clients[app] {
                    IslandPanelView(panel: panel, client: client, viewModel: viewModel)
                        .id(app)
                        .transition(.tabContent)
                } else {
                    switch viewModel.tab {
                    case .timer:
                        TimerPanel(viewModel: viewModel)
                            .transition(.tabContent)
                    case .pomodoro:
                        PomodoroPanel(viewModel: viewModel)
                            .transition(.tabContent)
                    case .stopwatch:
                        StopwatchPanel(model: viewModel.model, isVisible: isShown)
                            .transition(.tabContent)
                    case .worldClock:
                        WorldClockPanel(model: viewModel.model, isVisible: isShown)
                            .transition(.tabContent)
                    case .alarms:
                        AlarmsPanel(viewModel: viewModel)
                            .transition(.tabContent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 26)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: viewModel.tab)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: viewModel.activeAppTab)
    }
}

private extension AnyTransition {
    /// Tab content settles in with a small drift and fade; no blur, which is expensive at this size.
    static var tabContent: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        )
    }
}

/// Icon-only tabs to the left of the notch; the selected one sits in a sliding pill.
private struct TabSwitcher: View {
    let viewModel: NotchViewModel
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ExpandedTab.allCases) { tab in
                TabButton(symbol: tab.symbol, tint: tab.tint, title: tab.title,
                          isSelected: viewModel.activeAppTab == nil && viewModel.tab == tab,
                          isRunning: isRunning(tab), pill: pill) {
                    viewModel.select(tab)
                }
            }
            // Other apps' tabs, after cLockIn's own.
            ForEach(viewModel.model.island.panelApps) { client in
                let panel = viewModel.model.island.panels[client.app]
                TabButton(symbol: panel?.symbol ?? client.symbol, tint: Color(islandHex: panel?.tint) ?? client.color,
                          title: client.name, isSelected: viewModel.activeAppTab == client.app,
                          isRunning: false, pill: pill) {
                    viewModel.selectApp(client.app)
                }
            }
        }
    }

    private func isRunning(_ tab: ExpandedTab) -> Bool {
        let model = viewModel.model
        return switch tab {
        case .timer: model.timer.isActive
        case .pomodoro: model.pomodoro.isActive
        case .stopwatch: model.stopwatch.isActive
        case .alarms: model.alarms.nextAlarm != nil
        case .worldClock: false
        }
    }
}

private struct TabButton: View {
    let symbol: String
    let tint: Color
    let title: String
    let isSelected: Bool
    let isRunning: Bool
    let pill: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? tint : .white.opacity(hovering ? 0.85 : 0.5))
                .frame(width: 28, height: 24)
                .background {
                    if isSelected {
                        Capsule().fill(Color.white.opacity(0.14))
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isRunning && !isSelected {
                        Circle().fill(tint).frame(width: 5, height: 5).offset(x: -3, y: 3)
                            .transition(.scale)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(title)
    }
}
