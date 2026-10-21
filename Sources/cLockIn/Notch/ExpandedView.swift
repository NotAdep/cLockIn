import SwiftUI

/// The full panel: tabs and settings beside the notch, the selected feature below it.
struct ExpandedView: View {
    let viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabSwitcher(selection: Bindable(viewModel).tab, model: viewModel.model)
                Spacer(minLength: viewModel.notchSize.width + 12)
                Button {
                    viewModel.collapse()
                    SettingsWindowController.shared.show(model: viewModel.model)
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(CircleButtonStyle(size: 24))
                .help("Settings")
            }
            .padding(.horizontal, 16)
            .frame(height: viewModel.notchSize.height)

            ZStack {
                switch viewModel.tab {
                case .timer:
                    TimerPanel(viewModel: viewModel)
                        .transition(.push(from: .leading).combined(with: .opacity))
                case .pomodoro:
                    PomodoroPanel(viewModel: viewModel)
                        .transition(.push(from: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 26)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: viewModel.tab)
        .onChange(of: viewModel.tab) { viewModel.cancelDurationEntry() }
    }
}

private struct TabSwitcher: View {
    @Binding var selection: ExpandedTab
    let model: AppModel
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ExpandedTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                        Text(tab.title)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selection == tab ? .white : Theme.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background {
                        if selection == tab {
                            Capsule().fill(Color.white.opacity(0.14))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isRunning(tab) && selection != tab {
                            Circle().fill(tint(tab)).frame(width: 5, height: 5).offset(x: -3, y: 3)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isRunning(_ tab: ExpandedTab) -> Bool {
        switch tab {
        case .timer: model.timer.isActive
        case .pomodoro: model.pomodoro.isActive
        }
    }

    private func tint(_ tab: ExpandedTab) -> Color {
        switch tab {
        case .timer: Theme.timer
        case .pomodoro: Theme.tint(for: model.pomodoro.phase)
        }
    }
}
