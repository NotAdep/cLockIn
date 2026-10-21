import AppKit
import CLockInCore
import Observation
import SwiftUI

enum ActivityKind: Equatable {
    case timer
    case pomodoro
}

/// What the collapsed notch and the menu bar show while something is counting down.
struct LiveActivity: Equatable {
    var kind: ActivityKind
    var title: String
    var symbol: String
    var tint: Color
    var remaining: TimeInterval
    var progress: Double
    var isPaused: Bool
}

/// The "done" moment shown in the notch until it's dismissed.
struct NotchAlert: Equatable, Identifiable {
    enum Action: Equatable {
        case startNextPhase(PomodoroPhase)
    }

    let id = UUID()
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    var action: Action?
}

/// Owns the engines, keeps them ticking, and turns completions into alerts, sounds and notifications.
@MainActor
@Observable
final class AppModel {
    let timer: TimerEngine
    let pomodoro: PomodoroEngine
    let settings: AppSettings

    /// Refreshed by the ticker while anything runs; views read time through this.
    private(set) var now = Date()
    private(set) var alert: NotchAlert?

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let store: SnapshotStore
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    private enum Key {
        static let timer = "timerSnapshot"
        static let pomodoro = "pomodoroSnapshot"
    }

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        store = SnapshotStore(defaults: defaults)
        timer = TimerEngine()
        pomodoro = PomodoroEngine()
        if let saved = store.load(TimerSnapshot.self, key: Key.timer) { timer.restore(saved) }
        if let saved = store.load(PomodoroSnapshot.self, key: Key.pomodoro) { pomodoro.restore(saved) }

        timer.onChange = { [weak self] in self?.stateChanged() }
        timer.onFinish = { [weak self] in self?.timerFinished() }
        pomodoro.onChange = { [weak self] in self?.stateChanged() }
        pomodoro.onPhaseFinished = { [weak self] finished, next in self?.phaseFinished(finished, next: next) }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        stateChanged()
    }

    // MARK: Live activity

    /// The engine the collapsed notch follows: a running one beats a paused one; ties go to whichever ends first.
    var liveKind: ActivityKind? {
        switch (timer.isActive, pomodoro.isActive) {
        case (false, false): return nil
        case (true, false): return .timer
        case (false, true): return .pomodoro
        case (true, true):
            if timer.isRunning != pomodoro.isRunning { return timer.isRunning ? .timer : .pomodoro }
            return timer.remaining(at: now) <= pomodoro.remaining(at: now) ? .timer : .pomodoro
        }
    }

    var activity: LiveActivity? {
        liveKind.map(activity(for:))
    }

    func activity(for kind: ActivityKind) -> LiveActivity {
        switch kind {
        case .timer:
            LiveActivity(
                kind: .timer, title: "Timer", symbol: "timer", tint: Theme.timer,
                remaining: timer.remaining(at: now), progress: timer.progress(at: now), isPaused: timer.isPaused
            )
        case .pomodoro:
            LiveActivity(
                kind: .pomodoro, title: pomodoro.phase.title, symbol: Theme.symbol(for: pomodoro.phase),
                tint: Theme.tint(for: pomodoro.phase),
                remaining: pomodoro.remaining(at: now), progress: pomodoro.progress(at: now), isPaused: pomodoro.isPaused
            )
        }
    }

    func toggleLive() {
        switch liveKind {
        case .timer: timer.toggle()
        case .pomodoro: pomodoro.toggle()
        case nil: break
        }
    }

    // MARK: Alerts

    func dismissAlert() {
        alert = nil
    }

    func performAlertAction() {
        if case .startNextPhase = alert?.action { pomodoro.start() }
        alert = nil
    }

    #if DEBUG
    func debugShowAlert(_ alert: NotchAlert) {
        self.alert = alert
    }
    #endif

    private func timerFinished() {
        alert = NotchAlert(
            title: "Time's up",
            subtitle: "\(TimeFormat.short(timer.selectedDuration)) timer finished",
            symbol: "bell.fill",
            tint: Theme.timer
        )
        playFeedback()
    }

    private func phaseFinished(_ finished: PomodoroPhase, next: PomodoroPhase) {
        let title = finished == .focus ? "Focus complete" : "Break's over"
        let subtitle = pomodoro.config.autoAdvance
            ? "\(next.title) started"
            : "Up next: \(next.title.lowercased()), \(TimeFormat.short(pomodoro.config.duration(for: next)))"
        alert = NotchAlert(
            title: title,
            subtitle: subtitle,
            symbol: Theme.symbol(for: finished),
            tint: Theme.tint(for: finished),
            action: pomodoro.config.autoAdvance ? nil : .startNextPhase(next)
        )
        playFeedback()
    }

    private func playFeedback() {
        if settings.soundEnabled { SoundService.playChime() }
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
        syncNotifications()
        updateTicker()
    }

    private func updateTicker() {
        let needsTicks = timer.isRunning || pomodoro.isRunning
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

    /// System notifications back up the notch alert in case you're looking at another screen.
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
        NotificationService.shared.schedule(pending)
    }
}
