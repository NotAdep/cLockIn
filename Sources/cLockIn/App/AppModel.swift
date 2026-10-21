import AppKit
import CLockInCore
import Observation
import SwiftUI

enum ActivityKind: Equatable {
    case timer
    case pomodoro
    case stopwatch
    /// Something finished a while ago and is waiting to be acknowledged.
    case finished
}

/// What the collapsed notch and the menu bar show while something runs.
struct LiveActivity: Equatable {
    var kind: ActivityKind
    var title: String
    var symbol: String
    var tint: Color
    /// Time remaining for countdowns, time elapsed for the stopwatch, time overdue for a finished alert.
    var time: TimeInterval
    var progress: Double
    var isPaused: Bool

    /// The clock text for the compact notch and menu bar.
    var timeText: String {
        kind == .finished ? "+" + TimeFormat.clock(time) : TimeFormat.clock(time)
    }
}

/// The "done" moment shown in the notch until it's dismissed.
struct NotchAlert: Equatable, Identifiable {
    enum Action: Equatable {
        case startNextPhase(PomodoroPhase)
        case snooze(UUID)

        var title: String {
            switch self {
            case .startNextPhase: "Start"
            case .snooze: "Snooze"
            }
        }
    }

    let id = UUID()
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    var action: Action?
    var isAlarm = false
    var firedAt = Date()
}

/// Owns the engines, keeps them ticking, and turns completions into alerts and sounds.
@MainActor
@Observable
final class AppModel {
    /// How long a timer or Focus alert stays large before shrinking to a "+0:42" reminder.
    static let alertMinimizeDelay: TimeInterval = 30
    /// How long an alarm keeps ringing before it shrinks to a reminder.
    static let alarmRingDuration: TimeInterval = 120

    let timer: TimerEngine
    let pomodoro: PomodoroEngine
    let stopwatch: StopwatchEngine
    let alarms: AlarmEngine
    let settings: AppSettings

    /// Refreshed by the ticker while anything runs; views read time through this.
    private(set) var now = Date()
    private(set) var alert: NotchAlert?
    /// True once an unanswered alert has shrunk down to the compact notch.
    private(set) var isAlertMinimized = false
    private(set) var worldClocks: [WorldClockCity]

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var alarmTicker: Timer?
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private let store: SnapshotStore
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    private enum Key {
        static let timer = "timerSnapshot"
        static let pomodoro = "pomodoroSnapshot"
        static let stopwatch = "stopwatchSnapshot"
        static let alarms = "alarmSnapshot"
        static let worldClocks = "worldClocks"
    }

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        store = SnapshotStore(defaults: defaults)
        timer = TimerEngine()
        pomodoro = PomodoroEngine()
        stopwatch = StopwatchEngine()
        alarms = AlarmEngine()
        worldClocks = store.load([WorldClockCity].self, key: Key.worldClocks) ?? WorldClock.defaultCities
        if let saved = store.load(TimerSnapshot.self, key: Key.timer) { timer.restore(saved) }
        if let saved = store.load(PomodoroSnapshot.self, key: Key.pomodoro) { pomodoro.restore(saved) }
        if let saved = store.load(StopwatchSnapshot.self, key: Key.stopwatch) { stopwatch.restore(saved) }
        if let saved = store.load(AlarmSnapshot.self, key: Key.alarms) { alarms.restore(saved) }

        timer.onChange = { [weak self] in self?.stateChanged() }
        timer.onFinish = { [weak self] in self?.timerFinished() }
        pomodoro.onChange = { [weak self] in self?.stateChanged() }
        pomodoro.onPhaseFinished = { [weak self] finished, next in self?.phaseFinished(finished, next: next) }
        stopwatch.onChange = { [weak self] in self?.stateChanged() }
        alarms.onChange = { [weak self] in self?.stateChanged() }
        alarms.onFire = { [weak self] alarm in self?.alarmRang(alarm) }
        alarms.setSnoozeDuration(TimeInterval(settings.snoozeMinutes * 60))

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
                self?.alarms.tick()
            }
        }
        stateChanged()
    }

    // MARK: Live activity

    /// The engine the collapsed notch follows. An unanswered alert comes first; then anything running beats
    /// anything paused; countdowns beat the stopwatch, and among countdowns the one ending first wins.
    var liveKind: ActivityKind? {
        if alert != nil && isAlertMinimized { return .finished }
        var candidates: [(kind: ActivityKind, running: Bool, rank: TimeInterval)] = []
        if timer.isActive { candidates.append((.timer, timer.isRunning, timer.remaining(at: now))) }
        if pomodoro.isActive { candidates.append((.pomodoro, pomodoro.isRunning, pomodoro.remaining(at: now))) }
        if stopwatch.isActive { candidates.append((.stopwatch, stopwatch.isRunning, .infinity)) }
        return candidates.min { lhs, rhs in
            lhs.running != rhs.running ? lhs.running : lhs.rank < rhs.rank
        }?.kind
    }

    var activity: LiveActivity? {
        liveKind.map(activity(for:))
    }

    func activity(for kind: ActivityKind) -> LiveActivity {
        switch kind {
        case .timer:
            LiveActivity(
                kind: .timer, title: "Timer", symbol: "timer", tint: Theme.timer,
                time: timer.remaining(at: now), progress: timer.progress(at: now), isPaused: timer.isPaused
            )
        case .pomodoro:
            LiveActivity(
                kind: .pomodoro, title: pomodoro.phase.title, symbol: Theme.symbol(for: pomodoro.phase),
                tint: Theme.tint(for: pomodoro.phase),
                time: pomodoro.remaining(at: now), progress: pomodoro.progress(at: now), isPaused: pomodoro.isPaused
            )
        case .stopwatch:
            // The ring sweeps once a minute, like a second hand.
            LiveActivity(
                kind: .stopwatch, title: "Stopwatch", symbol: "stopwatch", tint: Theme.stopwatch,
                time: stopwatch.elapsed(at: now),
                progress: stopwatch.elapsed(at: now).truncatingRemainder(dividingBy: 60) / 60,
                isPaused: !stopwatch.isRunning
            )
        case .finished:
            LiveActivity(
                kind: .finished, title: alert?.title ?? "Done", symbol: alert?.symbol ?? "bell.fill",
                tint: alert?.tint ?? Theme.timer,
                time: max(0, now.timeIntervalSince(alert?.firedAt ?? now)), progress: 1, isPaused: false
            )
        }
    }

    func toggleLive() {
        switch liveKind {
        case .timer: timer.toggle()
        case .pomodoro: pomodoro.toggle()
        case .stopwatch: stopwatch.toggle()
        case .finished: dismissAlert()
        case nil: break
        }
    }

    // MARK: World clock

    func addWorldClock(_ city: WorldClockCity) {
        guard !worldClocks.contains(city) else { return }
        worldClocks.append(city)
        store.save(worldClocks, key: Key.worldClocks)
    }

    func removeWorldClock(_ city: WorldClockCity) {
        worldClocks.removeAll { $0 == city }
        store.save(worldClocks, key: Key.worldClocks)
    }

    func moveWorldClocks(from source: IndexSet, to destination: Int) {
        worldClocks.move(fromOffsets: source, toOffset: destination)
        store.save(worldClocks, key: Key.worldClocks)
    }

    // MARK: Alerts

    func dismissAlert() {
        alertTask?.cancel()
        alert = nil
        isAlertMinimized = false
        updateTicker()
    }

    /// Brings a shrunk alert back to full size.
    func restoreAlert() {
        isAlertMinimized = false
    }

    func setSnoozeMinutes(_ minutes: Int) {
        settings.snoozeMinutes = minutes.clamped(to: 1...60)
        alarms.setSnoozeDuration(TimeInterval(settings.snoozeMinutes * 60))
    }

    /// Shows a sample alert in the notch, so the alert settings can be tried out.
    func previewAlert(alarm: Bool = false) {
        present(alarm
            ? NotchAlert(title: "Alarm preview", subtitle: "This is how alarms ring", symbol: "alarm.fill",
                         tint: Theme.alarm, action: .snooze(UUID()), isAlarm: true)
            : NotchAlert(title: "Time's up", subtitle: "This is how timers finish", symbol: "bell.fill", tint: Theme.timer))
    }

    func performAlertAction() {
        switch alert?.action {
        case .startNextPhase: pomodoro.start()
        case .snooze(let id): alarms.snooze(id: id)
        case nil: break
        }
        dismissAlert()
    }

    #if DEBUG
    func debugShowAlert(_ alert: NotchAlert, minimized: Bool = false) {
        self.alert = alert
        isAlertMinimized = minimized
    }
    #endif

    private func timerFinished() {
        present(NotchAlert(
            title: "Time's up",
            subtitle: "\(TimeFormat.short(timer.selectedDuration)) timer finished",
            symbol: "bell.fill",
            tint: Theme.timer
        ))
    }

    private func phaseFinished(_ finished: PomodoroPhase, next: PomodoroPhase) {
        let title = finished == .focus ? "Focus complete" : "Break's over"
        let subtitle = pomodoro.config.autoAdvance
            ? "\(next.title) started"
            : "Up next: \(next.title.lowercased()), \(TimeFormat.short(pomodoro.config.duration(for: next)))"
        present(NotchAlert(
            title: title,
            subtitle: subtitle,
            symbol: Theme.symbol(for: finished),
            tint: Theme.tint(for: finished),
            action: pomodoro.config.autoAdvance ? nil : .startNextPhase(next)
        ))
    }

    private func alarmRang(_ alarm: Alarm) {
        let time = Calendar.current.date(from: DateComponents(hour: alarm.hour, minute: alarm.minute))
            .map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        present(NotchAlert(
            title: alarm.label,
            subtitle: time,
            symbol: "alarm.fill",
            tint: Theme.alarm,
            action: .snooze(alarm.id),
            isAlarm: true
        ))
    }

    /// Shows an alert and keeps reminding until it's answered: alarms ring every few seconds for two
    /// minutes; timers chime a few more times. Then the alert shrinks to a reminder in the compact notch.
    private func present(_ newAlert: NotchAlert) {
        alertTask?.cancel()
        alert = newAlert
        isAlertMinimized = false
        updateTicker()

        let sound: SoundService.Sound = newAlert.isAlarm ? .alarm : .chime
        let (interval, repeats): (TimeInterval, Int) = newAlert.isAlarm
            ? (3, Int(Self.alarmRingDuration / 3))
            : (10, settings.repeatAlertSound ? 3 : 0)
        let minimizeAfter = newAlert.isAlarm ? Self.alarmRingDuration : Self.alertMinimizeDelay
        if settings.soundEnabled { SoundService.play(sound) }

        alertTask = Task { [weak self] in
            let start = Date()
            var played = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, self.alert?.id == newAlert.id else { return }
                if played < repeats, self.settings.soundEnabled {
                    SoundService.play(sound)
                    played += 1
                }
                if Date().timeIntervalSince(start) >= minimizeAfter {
                    self.isAlertMinimized = true
                    if played >= repeats { return }
                }
            }
        }
    }

    // MARK: Ticking and persistence

    private func tick() {
        now = Date()
        timer.tick()
        pomodoro.tick()
    }

    private func stateChanged() {
        now = Date()
        store.save(timer.snapshot, key: Key.timer)
        store.save(pomodoro.snapshot, key: Key.pomodoro)
        store.save(stopwatch.snapshot, key: Key.stopwatch)
        store.save(alarms.snapshot, key: Key.alarms)
        syncNotifications()
        updateTicker()
        updateAlarmTicker()
    }

    /// Fast ticks drive the countdown and stopwatch displays; they stop when nothing is moving.
    private func updateTicker() {
        let needsTicks = timer.isRunning || pomodoro.isRunning || stopwatch.isRunning || alert != nil
        if needsTicks, ticker == nil {
            let ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            ticker.tolerance = 0.05
            RunLoop.main.add(ticker, forMode: .common)
            self.ticker = ticker
        } else if !needsTicks {
            ticker?.invalidate()
            ticker = nil
        }
    }

    /// Alarms are checked once a second, separately, so idle alarms don't redraw anything.
    private func updateAlarmTicker() {
        let needsTicks = alarms.needsChecking
        if needsTicks, alarmTicker == nil {
            let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.alarms.tick() }
            }
            ticker.tolerance = 0.2
            RunLoop.main.add(ticker, forMode: .common)
            alarmTicker = ticker
        } else if !needsTicks {
            alarmTicker?.invalidate()
            alarmTicker = nil
        }
    }

    /// Optional system notifications, for when the notch isn't in view.
    private func syncNotifications() {
        guard settings.systemNotificationsEnabled else {
            NotificationService.shared.schedule([])
            return
        }
        var pending: [NotificationService.Pending] = []
        if let end = timer.countdown.endDate {
            pending.append(.init(id: "timer", fireDate: end, title: "Time's up", body: "Your timer finished."))
        }
        if let end = pomodoro.countdown.endDate {
            let body = pomodoro.phase == .focus ? "Focus round complete. Take a break." : "Break's over. Back to focus."
            pending.append(.init(id: "pomodoro", fireDate: end, title: pomodoro.phase.title, body: body))
        }
        if let next = alarms.nextAlarm {
            pending.append(.init(id: "alarm", fireDate: next.date, title: next.alarm.label, body: "Alarm"))
        }
        NotificationService.shared.schedule(pending)
    }
}
