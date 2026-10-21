import AppKit
import CLockInCore
import Observation

/// Checks GitHub for a newer release. Only the request itself goes to GitHub; nothing about the user is sent.
@MainActor
@Observable
final class UpdateService {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case failed(String)
    }

    static let checkInterval: TimeInterval = 24 * 3600

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?

    private enum Key {
        static let lastChecked = "updateLastChecked"
        static let skipped = "updateSkippedVersion"
    }

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        lastChecked = defaults.object(forKey: Key.lastChecked) as? Date
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// "owner/name" of the GitHub repository releases come from.
    static var repository: String {
        Bundle.main.object(forInfoDictionaryKey: "GitHubRepository") as? String ?? "NotAdep/cLockIn"
    }

    /// The update to show, unless the user chose to skip that version.
    var availableUpdate: AvailableUpdate? {
        guard case .available(let update) = state, update.version != defaults.string(forKey: Key.skipped) else { return nil }
        return update
    }

    /// Checks shortly after launch and then about once a day, while automatic checks are on.
    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        guard settings.checkForUpdates else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval { return }
        Task { await check() }
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            lastChecked = Date()
            defaults.set(lastChecked, forKey: Key.lastChecked)
            if let release, let update = UpdateCheck.availableUpdate(currentVersion: Self.currentVersion, release: release) {
                state = .available(update)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed("Couldn't reach GitHub. Check your connection and try again.")
        }
    }

    func skip(_ update: AvailableUpdate) {
        defaults.set(update.version, forKey: Key.skipped)
        state = .upToDate
    }

    func download(_ update: AvailableUpdate) {
        NSWorkspace.shared.open(update.downloadURL ?? update.pageURL)
    }

    func openReleaseNotes(_ update: AvailableUpdate) {
        NSWorkspace.shared.open(update.pageURL)
    }

    /// The latest published release, or nil when the repository has none yet.
    private func fetchLatestRelease() async throws -> GitHubRelease? {
        let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("cLockIn/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try UpdateCheck.decodeRelease(from: data)
    }
}
