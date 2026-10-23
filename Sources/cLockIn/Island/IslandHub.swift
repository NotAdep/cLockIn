import AppKit
import CLockInCore
import Observation
import SwiftUI

/// An app that has asked to use the notch through the Island API.
struct IslandClient: Codable, Equatable, Identifiable {
    var app: String
    var name: String
    var symbol: String
    var tint: String?
    var callback: String?
    /// nil until you answer the permission prompt.
    var allowed: Bool?
    var token: String

    var id: String { app }
    var color: Color { Color(islandHex: tint) ?? .white }
}

/// Everything other apps have asked the notch to show, and who's allowed to ask.
@MainActor
@Observable
final class IslandHub {
    /// The expanded notch has room for this many app tabs next to cLockIn's own.
    static let maxPanelTabs = 3

    private(set) var clients: [String: IslandClient] = [:]
    private(set) var activities: [String: IslandActivity] = [:]
    private(set) var panels: [String: IslandPanel] = [:]

    @ObservationIgnored weak var model: AppModel?
    /// The port the server is listening on, for checking the Host header.
    @ObservationIgnored var port: UInt16 = IslandAPI.defaultPort
    @ObservationIgnored private var alertQueue: [(app: String, alert: IslandAlert)] = []
    @ObservationIgnored private var permissionQueue: [String] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session = URLSession(configuration: .ephemeral)

    private static let clientsKey = "islandClients"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.clientsKey),
           let saved = try? JSONDecoder().decode([IslandClient].self, from: data) {
            clients = Dictionary(uniqueKeysWithValues: saved.map { ($0.app, $0) })
        }
    }

    // MARK: What the notch reads

    var orderedClients: [IslandClient] {
        clients.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Apps with their own tab in the expanded notch.
    var panelApps: [IslandClient] {
        Array(orderedClients.filter { $0.allowed == true && panels[$0.app] != nil }.prefix(Self.maxPanelTabs))
    }

    /// Pills from allowed apps, most important first.
    var visibleActivities: [(client: IslandClient, activity: IslandActivity)] {
        orderedClients.compactMap { client in
            guard client.allowed == true, let activity = activities[client.app] else { return nil }
            return (client, activity)
        }
        .sorted { ($0.activity.priority ?? .normal) > ($1.activity.priority ?? .normal) }
    }

    var hasVisibleActivity: Bool { !visibleActivities.isEmpty }

    // MARK: Requests

    func handle(_ request: IslandHTTPRequest) -> (status: Int, body: Data) {
        guard IslandHTTP.isLocalHost(request.headers["host"], port: port) else {
            return error(403, "requests must be addressed to 127.0.0.1")
        }
        guard request.headers[IslandAPI.clientHeader] != nil else {
            return error(403, "missing \(IslandAPI.clientHeader) header")
        }
        guard let route = IslandRoute(path: request.path) else { return error(404, "unknown path") }

        switch (route, request.method) {
        case (.status, "GET"):
            return json(200, ["version": IslandAPI.version, "apps": orderedClients.filter { $0.allowed == true }.map(\.name)])
        case (.register, "POST"):
            guard let registration = decode(IslandRegistration.self, request.body) else { return error(400, "bad registration") }
            return register(registration)
        case (.activity(let app), "PUT"), (.activity(let app), "POST"):
            if let denied = authorize(app, request) { return denied }
            guard let activity = decode(IslandActivity.self, request.body) else { return error(400, "bad activity") }
            if activities[app] != activity.sanitized { activities[app] = activity.sanitized }
            return json(200, ["ok": true])
        case (.activity(let app), "DELETE"):
            if let denied = authorize(app, request) { return denied }
            activities[app] = nil
            return json(200, ["ok": true])
        case (.panel(let app), "PUT"), (.panel(let app), "POST"):
            if let denied = authorize(app, request) { return denied }
            guard let panel = decode(IslandPanel.self, request.body) else { return error(400, "bad panel") }
            if panels[app] != panel.sanitized { panels[app] = panel.sanitized }
            return json(200, ["ok": true])
        case (.panel(let app), "DELETE"):
            if let denied = authorize(app, request) { return denied }
            panels[app] = nil
            return json(200, ["ok": true])
        case (.alert(let app), "POST"):
            if let denied = authorize(app, request) { return denied }
            guard let alert = decode(IslandAlert.self, request.body) else { return error(400, "bad alert") }
            alertQueue.append((app, alert.sanitized))
            showNextAlert()
            return json(202, ["queued": true])
        default:
            return error(405, "method not allowed")
        }
    }

    private func register(_ registration: IslandRegistration) -> (status: Int, body: Data) {
        guard IslandRoute.isValidApp(registration.app) else { return error(400, "bad app id") }
        if let callback = registration.callback, !Self.isLocalCallback(callback) {
            return error(400, "callback must be http://127.0.0.1:<port>/…")
        }
        var client = clients[registration.app] ?? IslandClient(
            app: registration.app, name: registration.name, symbol: "app.badge.fill",
            tint: nil, callback: nil, allowed: nil, token: UUID().uuidString
        )
        client.name = String(registration.name.prefix(30))
        client.symbol = registration.symbol ?? client.symbol
        client.tint = registration.tint ?? client.tint
        client.callback = registration.callback
        clients[client.app] = client
        save()

        switch client.allowed {
        case true?:
            return json(200, ["status": "allowed", "token": client.token, "version": IslandAPI.version])
        case false?:
            return json(403, ["status": "denied"])
        case nil:
            if !permissionQueue.contains(client.app) {
                permissionQueue.append(client.app)
                showNextAlert()
            }
            return json(202, ["status": "pending"])
        }
    }

    /// Nil when the app may post; otherwise the response explaining why not.
    private func authorize(_ app: String, _ request: IslandHTTPRequest) -> (status: Int, body: Data)? {
        guard let client = clients[app] else { return json(403, ["status": "unknown", "error": "register first"]) }
        guard client.allowed == true else {
            return json(403, ["status": client.allowed == false ? "denied" : "pending"])
        }
        guard request.headers[IslandAPI.tokenHeader] == client.token else { return error(403, "bad token") }
        return nil
    }

    // MARK: Permission

    func setAllowed(_ allowed: Bool, for app: String) {
        guard var client = clients[app] else { return }
        client.allowed = allowed
        clients[app] = client
        if !allowed {
            activities[app] = nil
            panels[app] = nil
            alertQueue.removeAll { $0.app == app }
        }
        permissionQueue.removeAll { $0 == app }
        save()
    }

    /// Removes an app entirely; it will ask again next time it connects.
    func forget(_ app: String) {
        clients[app] = nil
        activities[app] = nil
        panels[app] = nil
        alertQueue.removeAll { $0.app == app }
        permissionQueue.removeAll { $0 == app }
        save()
    }

    // MARK: Alerts

    /// Shows the next permission prompt or alert, once the notch isn't showing another alert.
    func showNextAlert() {
        guard let model, model.shownAlert == nil else { return }
        if let app = permissionQueue.first, let client = clients[app] {
            permissionQueue.removeFirst()
            model.presentIslandAlert(NotchAlert(
                title: "\(client.name) wants to use the notch",
                subtitle: "It can show alerts, a pill beside the notch and its own tab.",
                symbol: client.symbol, tint: client.color,
                source: .permission(app: app),
                buttons: [
                    .init(id: "allow", title: "Allow", prominent: true),
                    .init(id: "deny", title: "Don't Allow", prominent: false),
                ],
                header: "cLockIn"
            ), duration: 60, sound: true)
            return
        }
        while let (app, alert) = alertQueue.first {
            alertQueue.removeFirst()
            guard let client = clients[app], client.allowed == true else { continue }
            let tint = Color(islandHex: alert.tint) ?? client.color
            model.presentIslandAlert(NotchAlert(
                title: alert.title,
                subtitle: alert.subtitle ?? "",
                symbol: alert.symbol ?? client.symbol,
                tint: tint,
                source: .island(app: app, alertID: alert.id ?? ""),
                buttons: (alert.buttons ?? []).map {
                    .init(id: $0.id, title: $0.label, prominent: $0.prominent ?? false, url: $0.url.flatMap(Self.openableURL))
                },
                header: client.name
            ), duration: alert.duration ?? 8, sound: alert.sound ?? true)
            return
        }
    }

    /// A button on an alert from (or about) another app.
    func pressed(_ button: NotchAlert.Button, on alert: NotchAlert) {
        switch alert.source {
        case .permission(let app):
            setAllowed(button.id == "allow", for: app)
        case .island(let app, let alertID):
            if let url = button.url {
                NSWorkspace.shared.open(url)
            } else {
                send(IslandEvent(app: app, source: "alert", target: alertID.isEmpty ? nil : alertID, action: button.id))
            }
        case .clock:
            break
        }
    }

    /// A button in an app's tab, on a row or in the footer.
    func pressed(_ button: IslandButton, app: String, row: String?) {
        if let url = button.url.flatMap(Self.openableURL) {
            NSWorkspace.shared.open(url)
        } else {
            send(IslandEvent(app: app, source: row == nil ? "footer" : "panel", target: row, action: button.id))
        }
    }

    func open(_ urlString: String?) {
        if let url = urlString.flatMap(Self.openableURL) { NSWorkspace.shared.open(url) }
    }

    // MARK: Plumbing

    private func send(_ event: IslandEvent) {
        guard let client = clients[event.app], client.allowed == true,
              let callback = client.callback, let url = URL(string: callback),
              let body = try? JSONEncoder().encode(event) else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.token, forHTTPHeaderField: IslandAPI.tokenHeader)
        request.httpBody = body
        session.dataTask(with: request).resume()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Array(clients.values)) { defaults.set(data, forKey: Self.clientsKey) }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    private func json(_ status: Int, _ object: [String: Any]) -> (status: Int, body: Data) {
        (status, (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8))
    }

    private func error(_ status: Int, _ message: String) -> (status: Int, body: Data) {
        json(status, ["error": message])
    }

    static func isLocalCallback(_ string: String) -> Bool {
        guard let url = URL(string: string), url.scheme == "http" else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "")
    }

    /// Only web links; apps can't make the notch launch arbitrary URL schemes.
    static func openableURL(_ string: String) -> URL? {
        guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}

extension Color {
    /// A color from the Island API's "#rrggbb".
    init?(islandHex hex: String?) {
        guard let (r, g, b) = IslandColor.rgb(hex) else { return nil }
        self.init(red: r, green: g, blue: b)
    }
}
