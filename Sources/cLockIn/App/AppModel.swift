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
    /// Shown for another app through the Island API.
    case island
}

/// One thing the collapsed notch and the menu bar can show while it runs.
struct LiveActivity: Equatable, Identifiable {
    var id: String
    var kind: ActivityKind
    var title: String
    var symbol: String
    var tint: Color
    /// Time remaining for countdowns, time elapsed for the stopwatch, time overdue for a finished alert.
    var time: TimeInterval
    var progress: Double
    var isPaused: Bool
    /// Set for timers, so the panel can open on the right one.
    var timerID: UUID? = nil
    /// Text another app supplied in place of a time, like "2d".
    var text: String? = nil
    /// The app an island activity came from, so the panel can open on its tab.
    var appID: String? = nil
    var showsRing = true

    /// The clock text for the compact notch and menu bar.
    var timeText: String {
        if let text { return text }
        return kind == .finished ? "+" + TimeFormat.clock(time) : TimeFormat.clock(time)
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

    /// Who the alert is from: cLockIn itself, or another app through the Island API.
    enum Source: Equatable {
        case clock
        case island(app: String, alertID: String)
        /// Asking whether an app may use the notch.
        case permission(app: String)
    }

    /// Buttons supplied by another app, in place of `action`.
    struct Button: Equatable, Identifiable {
        var id: String
        var title: String
        var prominent: Bool
        var url: URL? = nil
    }

    let id = UUID()
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    var action: Action?
    var isAlarm = false
    var firedAt = Date()
    var source: Source = .clock
    var buttons: [Button] = []
    /// Replaces "Done" or "Alarm" beside the notch, e.g. the name of the app that sent it.
    var header: String? = nil
}

/// Owns the engines, keeps them ticking, and turns completions into alerts and sounds.
@MainActor
@Observable
final class AppModel {
    /// How long a timer or Focus alert stays large before shrinking to a "+0:42" reminder.
    static let alertMinimizeDelay: TimeInterval = 30
    /// How long an alarm keeps ringing before it shrinks to a reminder.
    static let alarmRingDuration: TimeInterval = 120
    /// The collapsed notch shows at most this many activities, one on each side.
    static let maxCompactActivities = 2

    let timer: TimerEngine
    let pomodoro: PomodoroEngine
    let stopwatch: StopwatchEngine
    let alarms: AlarmEngine
    let history: FocusHistory
    let settings: AppSettings
    let updates: UpdateService
    /// Content other apps have sent to the notch.
    let island: IslandHub

    /// The time views draw with. The ticker only moves it when a displayed second actually changes,
    /// so a running timer redraws once a second instead of on every tick.
    private(set) var now = Date()
    private(set) var alert: NotchAlert?
    /// True once an unanswered alert has shrunk down to the compact notch.
    private(set) var isAlertMinimized = false
    /// An alert from another app. It only shows while cLockIn's own alert isn't on screen.
    private(set) var islandAlert: NotchAlert?
    private(set) var worldClocks: [WorldClockCity]

    @ObservationIgnored private var ticker: Timer?
    /// The whole seconds currently on screen, to tell when `now` needs to move.
    @ObservationIgnored private var displayedSeconds: [Int] = []
    @ObservationIgnored private var alarmTicker: Timer?
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var islandAlertTask: Task<Void, Never>?
    @ObservationIgnored private let store: SnapshotStore
    @ObservationIgnored private let historyFile: URL?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var wasFocusing = false

    private enum Key {
        static let timer = "timerSnapshot"
        static let pomodoro = "pomodoroSnapshot"
        static let stopwatch = "stopwatchSnapshot"
        static let alarms = "alarmSnapshot"
        static let worldClocks = "worldClocks"
    }

    /// Where focus history is kept: a JSON file, since it grows over time.
    nonisolated static var defaultHistoryFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("cLockIn", isDirectory: true)
            .appendingPathComponent("focus-history.json")
    }

    init(settings: AppSettings, defaults: UserDefaults = .standard, historyFile: URL? = AppModel.defaultHistoryFile) {
        self.settings = settings
        updates = UpdateService(settings: settings, defaults: defaults)
        island = IslandHub(defaults: defaults)
        store = SnapshotStore(defaults: defaults)
        self.historyFile = historyFile
        timer = TimerEngine()
        pomodoro = PomodoroEngine()
        stopwatch = StopwatchEngine()
        alarms = AlarmEngine()
        history = FocusHistory()
        worldClocks = store.load([WorldClockCity].self, key: Key.worldClocks) ?? WorldClock.defaultCities
        if let saved = store.load(TimerSnapshot.self, key: Key.timer) { timer.restore(saved) }
        if let saved = store.load(StopwatchSnapshot.self, key: Key.stopwatch) { stopwatch.restore(saved) }
        if let saved = store.load(AlarmSnapshot.self, key: Key.alarms) { alarms.restore(saved) }
        if let historyFile, let data = try? Data(contentsOf: historyFile),
           let saved = try? JSONDecoder().decode(FocusHistorySnapshot.self, from: data) {
            history.restore(saved)
        }
        // Hooked up before restoring, so a round that finished while the app was closed is recorded.
        pomodoro.onFocusSession = { [weak self] session in self?.history.record(session) }
        if let saved = store.load(PomodoroSnapshot.self, key: Key.pomodoro) { pomodoro.restore(saved) }

        timer.onChange = { [weak self] in self?.stateChanged() }
        timer.onFinish = { [weak self] finished in self?.timerFinished(finished) }
        pomodoro.onChange = { [weak self] in self?.stateChanged() }
        pomodoro.onPhaseFinished = { [weak self] finished, next in self?.phaseFinished(finished, next: next) }
        stopwatch.onChange = { [weak self] in self?.stateChanged() }
        alarms.onChange = { [weak self] in self?.stateChanged() }
        alarms.onFire = { [weak self] alarm in self?.alarmRang(alarm) }
        alarms.setSnoozeDuration(TimeInterval(settings.snoozeMinutes * 60))
        history.onChange = { [weak self] in self?.saveHistory() }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
                self?.alarms.tick()
            }
        }
        wasFocusing = isFocusing
        island.model = self
        stateChanged()
    }

    // MARK: Live activities

    /// Everything that could appear in the collapsed notch, most important first: an unanswered alert,
    /// then anything running before anything paused; countdowns by time left, the stopwatch last.
    /// Other apps' pills slot in by priority: high ones before cLockIn's running activities, normal ones
    /// before paused ones, low ones last.
    var activities: [LiveActivity] {
        var running: [(rank: TimeInterval, activity: LiveActivity)] = []
        var paused: [(rank: TimeInterval, activity: LiveActivity)] = []
        func add(_ activity: LiveActivity, rank: TimeInterval) {
            if activity.isPaused { paused.append((rank, activity)) } else { running.append((rank, activity)) }
        }
        for item in timer.timers {
            add(timerActivity(item), rank: item.countdown.remaining(at: now))
        }
        if pomodoro.isActive { add(pomodoroActivity, rank: pomodoro.remaining(at: now)) }
        if stopwatch.isActive { add(stopwatchActivity, rank: .infinity) }

        let appPills = island.visibleActivities.map { item in
            (priority: item.activity.priority ?? .normal, activity: islandActivity(item.client, item.activity))
        }
        func fromApps(_ priority: IslandPriority) -> [LiveActivity] {
            appPills.filter { $0.priority == priority }.map(\.activity)
        }

        var ordered = fromApps(.high)
            + running.sorted { $0.rank < $1.rank }.map(\.activity)
            + fromApps(.normal)
            + paused.sorted { $0.rank < $1.rank }.map(\.activity)
            + fromApps(.low)
        if let finished = finishedActivity { ordered.insert(finished, at: 0) }
        return ordered
    }

    private func islandActivity(_ client: IslandClient, _ activity: IslandActivity) -> LiveActivity {
        LiveActivity(
            id: "island-\(client.app)", kind: .island, title: activity.title ?? client.name,
            symbol: activity.symbol ?? client.symbol, tint: Color(islandHex: activity.tint) ?? client.color,
            time: 0, progress: activity.progress ?? 0, isPaused: false,
            text: activity.text, appID: client.app, showsRing: activity.progress != nil
        )
    }

    /// What the collapsed notch shows: up to two activities.
    var compactActivities: [LiveActivity] {
        Array(activities.prefix(Self.maxCompactActivities))
    }

    var activity: LiveActivity? { activities.first }

    /// Whether anything is showing, without reading the clock, for views that shouldn't redraw every second.
    var hasLiveActivity: Bool {
        timer.isActive || pomodoro.isActive || stopwatch.isActive || (alert != nil && isAlertMinimized)
            || island.hasVisibleActivity
    }

    /// A one-line summary for the menu that never reads the clock: what's running and whether it's paused.
    var menuSummary: (title: String, isPaused: Bool)? {
        if let alert, isAlertMinimized { return (alert.title, false) }
        if let item = timer.primary { return ("\(item.label) timer", item.countdown.isPaused) }
        if pomodoro.isActive { return (pomodoro.label ?? pomodoro.phase.title, pomodoro.isPaused) }
        if stopwatch.isActive { return ("Stopwatch", !stopwatch.isRunning) }
        if let other = island.visibleActivities.first {
            return (other.activity.title ?? "\(other.client.name): \(other.activity.text)", false)
        }
        return nil
    }
    var liveKind: ActivityKind? { activity?.kind }

    private func timerActivity(_ item: RunningTimer) -> LiveActivity {
        LiveActivity(
            id: "timer-\(item.id)", kind: .timer, title: "\(item.label) timer", symbol: "timer", tint: Theme.timer,
            time: item.countdown.remaining(at: now), progress: item.countdown.progress(at: now),
            isPaused: item.countdown.isPaused, timerID: item.id
        )
    }

    private var pomodoroActivity: LiveActivity {
        LiveActivity(
            id: "pomodoro", kind: .pomodoro, title: pomodoro.label ?? pomodoro.phase.title,
            symbol: Theme.symbol(for: pomodoro.phase), tint: Theme.tint(for: pomodoro.phase),
            time: pomodoro.remaining(at: now), progress: pomodoro.progress(at: now), isPaused: pomodoro.isPaused
        )
    }

    /// The ring sweeps once a minute, like a second hand.
    private var stopwatchActivity: LiveActivity {
        let elapsed = stopwatch.elapsed(at: now)
        return LiveActivity(
            id: "stopwatch", kind: .stopwatch, title: "Stopwatch", symbol: "stopwatch", tint: Theme.stopwatch,
            time: elapsed, progress: elapsed.truncatingRemainder(dividingBy: 60) / 60, isPaused: !stopwatch.isRunning
        )
    }

    private var finishedActivity: LiveActivity? {
        guard let alert, isAlertMinimized else { return nil }
        return LiveActivity(
            id: "finished", kind: .finished, title: alert.title, symbol: alert.symbol, tint: alert.tint,
            time: max(0, now.timeIntervalSince(alert.firedAt)), progress: 1, isPaused: false
        )
    }

    /// Pause or resume whatever the notch is showing first.
    func toggleLive() {
        guard let activity else { return }
        switch activity.kind {
        case .timer: if let id = activity.timerID { timer.toggle(id: id) }
        case .pomodoro: pomodoro.toggle()
        case .stopwatch: stopwatch.toggle()
        case .finished: dismissAlert()
        case .island: break
        }
    }

    // MARK: Focus

    private var isFocusing: Bool { pomodoro.phase == .focus && pomodoro.isRunning }

    /// Runs the user's Do Not Disturb shortcuts when a focus round starts or stops.
    private func updateFocusMode() {
        let focusing = isFocusing
        guard focusing != wasFocusing else { return }
        wasFocusing = focusing
        guard settings.focusModeEnabled else { return }
        FocusModeService.run(focusing ? settings.focusOnShortcut : settings.focusOffShortcut)
    }

    private func saveHistory() {
        guard let historyFile, let data = try? JSONEncoder().encode(history.snapshot) else { return }
        try? FileManager.default.createDirectory(at: historyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: historyFile, options: .atomic)
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
        island.showNextAlert()
    }

    /// The alert the notch shows right now: cLockIn's own, unless it has shrunk to a reminder;
    /// then one from another app, if any.
    var shownAlert: NotchAlert? {
        if let alert, !isAlertMinimized { return alert }
        return islandAlert
    }

    /// Dismisses whichever alert is on screen.
    func dismissShownAlert() {
        if alert != nil && !isAlertMinimized { dismissAlert() } else { dismissIslandAlert() }
    }

    /// Another app's alert. It closes on its own after `duration`; it never shrinks to a reminder.
    func presentIslandAlert(_ newAlert: NotchAlert, duration: TimeInterval, sound: Bool) {
        islandAlertTask?.cancel()
        islandAlert = newAlert
        if sound, settings.soundEnabled { SoundService.play(.chime) }
        islandAlertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.islandAlert?.id == newAlert.id else { return }
            self.dismissIslandAlert()
        }
    }

    func dismissIslandAlert() {
        islandAlertTask?.cancel()
        islandAlert = nil
        island.showNextAlert()
    }

    func pressIslandButton(_ button: NotchAlert.Button) {
        guard let current = islandAlert else { return }
        island.pressed(button, on: current)
        dismissIslandAlert()
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
    func debugShowIslandAlert(_ alert: NotchAlert) {
        islandAlert = alert
    }

    func debugShowAlert(_ alert: NotchAlert, minimized: Bool = false) {
        self.alert = alert
        isAlertMinimized = minimized
    }
    #endif

    private func timerFinished(_ finished: RunningTimer) {
        present(NotchAlert(
            title: "Time's up",
            subtitle: "\(finished.label) timer finished",
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
                    if !self.isAlertMinimized {
                        self.isAlertMinimized = true
                        // The notch is free again: other apps' alerts can show.
                        self.island.showNextAlert()
                    }
                    if played >= repeats { return }
                }
            }
        }
    }

    // MARK: Ticking and persistence

    private func tick() {
        let date = Date()
        timer.tick()
        pomodoro.tick()
        let seconds = displaySeconds(at: date)
        guard seconds != displayedSeconds else { return }
        displayedSeconds = seconds
        now = date
    }

    /// Every number of seconds the notch or panel shows, rounded the way it's displayed.
    private func displaySeconds(at date: Date) -> [Int] {
        func countdown(_ remaining: TimeInterval) -> Int { Int((remaining - 0.001).rounded(.up)) }
        return timer.timers.map { countdown($0.countdown.remaining(at: date)) } + [
            countdown(pomodoro.remaining(at: date)),
            Int(stopwatch.elapsed(at: date)),
            alert.map { Int(date.timeIntervalSince($0.firedAt)) } ?? -1,
        ]
    }

    private func stateChanged() {
        now = Date()
        displayedSeconds = displaySeconds(at: now)
        store.save(timer.snapshot, key: Key.timer)
        store.save(pomodoro.snapshot, key: Key.pomodoro)
        store.save(stopwatch.snapshot, key: Key.stopwatch)
        store.save(alarms.snapshot, key: Key.alarms)
        syncNotifications()
        updateTicker()
        updateAlarmTicker()
        updateFocusMode()
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
        var pending: [NotificationService.Pending] = timer.timers.compactMap { item in
            item.countdown.endDate.map {
                .init(id: "timer-\(item.id)", fireDate: $0, title: "Time's up", body: "Your \(item.label) timer finished.")
            }
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
