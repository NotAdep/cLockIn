import AppKit
import Charts
import CLockInCore
import SwiftUI
import UniformTypeIdentifiers

/// The full Focus statistics, in a normal window: totals, a chart by label, sessions and label management.
@MainActor
final class FocusStatsWindowController {
    static let shared = FocusStatsWindowController()
    private(set) var window: NSWindow?
    private let state = FocusStatsState()

    func show(model: AppModel, editingLabels: Bool = false) {
        if editingLabels { state.showsLabelEditor = true }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: FocusStatsView(model: model, state: state)))
            window.title = "Focus Statistics"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 780, height: 680))
            window.minSize = NSSize(width: 680, height: 520)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
@Observable
final class FocusStatsState {
    var showsLabelEditor = false
}

enum StatsRange: String, CaseIterable, Identifiable {
    case week, month

    var id: Self { self }
    var title: String { self == .week ? "7 days" : "30 days" }
    var days: Int { self == .week ? 7 : 30 }
}

struct FocusStatsView: View {
    let model: AppModel
    @Bindable var state: FocusStatsState
    @State private var range: StatsRange = .week
    @State private var confirmClear = false

    private var history: FocusHistory { model.history }

    var body: some View {
        // Statistics only change when a session is recorded; once a minute keeps "today" honest.
        TimelineView(.everyMinute) { context in
            let now = context.date
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    SummaryCards(history: history, now: now)
                    chartSection(now: now)
                    HStack(alignment: .top, spacing: 20) {
                        LabelBreakdown(history: history, range: range, now: now)
                        LabelEditor(model: model, isExpanded: $state.showsLabelEditor)
                    }
                    SessionList(history: history)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .confirmationDialog("Delete all focus history?", isPresented: $confirmClear) {
            Button("Delete History", role: .destructive) { history.clear() }
        } message: {
            Text("This removes every recorded session. Labels are kept. It can't be undone.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus").font(.largeTitle.weight(.bold))
                Text("\(history.sessions.count) sessions recorded")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                exportCSV()
            } label: {
                Label("Export CSV…", systemImage: "square.and.arrow.up")
            }
            .disabled(history.sessions.isEmpty)
            Menu {
                Button("Delete All History…", role: .destructive) { confirmClear = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func chartSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Focus time").font(.title3.weight(.semibold))
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(StatsRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            FocusChart(days: history.days(range.days, endingAt: now), labels: history.labels, range: range)
                .frame(height: 220)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "cLockIn Focus \(Date().formatted(.iso8601.year().month().day())).csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? history.csv().write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// A stable colour per label, in the order labels were created.
enum LabelPalette {
    static let colors: [Color] = [
        Theme.focus, Theme.stopwatch, Theme.shortBreak, Theme.worldClock, Theme.timer, Theme.alarm, Theme.longBreak,
    ]

    static func color(for label: String, in labels: [String]) -> Color {
        guard label != FocusHistory.unlabeled, let index = labels.firstIndex(of: label) else { return Color.gray }
        return colors[index % colors.count]
    }
}

private struct SummaryCards: View {
    let history: FocusHistory
    let now: Date

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let week = DateInterval(start: calendar.date(byAdding: .day, value: -6, to: today)!, end: now)
        let all = DateInterval(start: .distantPast, end: now)
        HStack(spacing: 12) {
            card("Today", value: history.totalFocused(in: DateInterval(start: today, end: now)),
                 detail: "\(history.sessions(in: DateInterval(start: today, end: now)).filter(\.completed).count) rounds")
            card("Last 7 days", value: history.totalFocused(in: week),
                 detail: "\(history.sessions(in: week).filter(\.completed).count) rounds")
            streakCard(history.streak(at: now))
            card("All time", value: history.totalFocused(in: all), detail: "\(history.sessions.filter(\.completed).count) rounds")
        }
    }

    private func card(_ title: String, value: TimeInterval, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value > 0 ? TimeFormat.short(value) : "0m")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func streakCard(_ streak: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Streak").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? Theme.timer : .secondary)
                Text("\(streak) \(streak == 1 ? "day" : "days")")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
            }
            Text("In a row, with a finished round").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

private struct FocusChart: View {
    struct Bar: Identifiable {
        let id = UUID()
        let day: Date
        let label: String
        let minutes: Double
    }

    let days: [FocusDay]
    let labels: [String]
    let range: StatsRange

    var body: some View {
        let bars = days.flatMap { day in
            day.byLabel.map { Bar(day: day.day, label: $0.key, minutes: $0.value / 60) }
        }
        let shownLabels = Array(Set(bars.map(\.label))).sorted { lhs, rhs in
            (labels.firstIndex(of: lhs) ?? .max) < (labels.firstIndex(of: rhs) ?? .max)
        }
        if bars.isEmpty {
            ContentUnavailableView(
                "No focus time yet",
                systemImage: "chart.bar",
                description: Text("Finished and partial focus rounds show up here.")
            )
        } else {
            Chart(bars) { bar in
                BarMark(
                    x: .value("Day", bar.day, unit: .day),
                    y: .value("Minutes", bar.minutes)
                )
                .foregroundStyle(by: .value("Label", bar.label))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(
                domain: shownLabels,
                range: shownLabels.map { LabelPalette.color(for: $0, in: labels) }
            )
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: range == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) { Text(TimeFormat.short(minutes * 60)) }
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
        }
    }
}

private struct LabelBreakdown: View {
    let history: FocusHistory
    let range: StatsRange
    let now: Date

    var body: some View {
        let start = Calendar.current.date(byAdding: .day, value: -(range.days - 1), to: Calendar.current.startOfDay(for: now))!
        let totals = history.totalsByLabel(in: DateInterval(start: start, end: now))
        let sum = max(totals.reduce(0) { $0 + $1.focused }, 1)
        VStack(alignment: .leading, spacing: 10) {
            Text("By label, \(range.title)").font(.title3.weight(.semibold))
            if totals.isEmpty {
                Text("Nothing yet").foregroundStyle(.secondary)
            }
            ForEach(totals, id: \.label) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(LabelPalette.color(for: item.label, in: history.labels)).frame(width: 8, height: 8)
                        Text(item.label)
                        Spacer()
                        Text(TimeFormat.short(item.focused)).monospacedDigit().foregroundStyle(.secondary)
                        Text("\(Int((item.focused / sum * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(LabelPalette.color(for: item.label, in: history.labels).opacity(0.8))
                            .frame(width: proxy.size.width * item.focused / sum)
                    }
                    .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

/// Add, rename and remove labels. Renaming updates past sessions too.
private struct LabelEditor: View {
    let model: AppModel
    @Binding var isExpanded: Bool
    @State private var newLabel = ""
    @State private var renaming: String?
    @State private var renameText = ""

    private var history: FocusHistory { model.history }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Labels").font(.title3.weight(.semibold))
                Spacer()
            }
            HStack {
                TextField("New label", text: $newLabel, prompt: Text("e.g. Thesis"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if history.labels.isEmpty {
                Text("Labels let you see where your focus time goes. Pick one in the Focus tab before you start.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(history.labels, id: \.self) { label in
                HStack(spacing: 8) {
                    Circle().fill(LabelPalette.color(for: label, in: history.labels)).frame(width: 8, height: 8)
                    if renaming == label {
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commitRename(label) }
                        Button("Save") { commitRename(label) }
                    } else {
                        Text(label)
                        if model.pomodoro.label == label {
                            Text("current").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            renaming = label
                            renameText = label
                        } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help("Rename")
                        Button {
                            if model.pomodoro.label == label { model.pomodoro.setLabel(nil) }
                            history.removeLabel(label)
                        } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                            .buttonStyle(.borderless)
                            .help("Remove from the list (past sessions keep it)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func add() {
        history.addLabel(newLabel)
        newLabel = ""
    }

    private func commitRename(_ label: String) {
        history.renameLabel(label, to: renameText)
        if model.pomodoro.label == label { model.pomodoro.setLabel(renameText.trimmingCharacters(in: .whitespaces)) }
        renaming = nil
    }
}

private struct SessionList: View {
    let history: FocusHistory
    private static let shown = 50

    var body: some View {
        let recent = Array(history.sessions.sorted { $0.end > $1.end }.prefix(Self.shown))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent sessions").font(.title3.weight(.semibold))
                Spacer()
                if history.sessions.count > Self.shown {
                    Text("Latest \(Self.shown) of \(history.sessions.count). Export for all of them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if recent.isEmpty {
                Text("Nothing yet").foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(recent) { session in
                    HStack {
                        Text(session.end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .frame(width: 110, alignment: .leading)
                        Text("\(session.start.formatted(date: .omitted, time: .shortened)) – \(session.end.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        Text(TimeFormat.short(session.focused)).monospacedDigit()
                            .frame(width: 70, alignment: .leading)
                        if let label = session.label {
                            Label(label, systemImage: "tag.fill")
                                .foregroundStyle(LabelPalette.color(for: label, in: history.labels))
                        }
                        Spacer()
                        Image(systemName: session.completed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(session.completed ? Color.green : Color.secondary)
                            .help(session.completed ? "Finished" : "Cut short")
                    }
                    .font(.callout)
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}
