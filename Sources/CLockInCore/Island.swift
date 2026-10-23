import Foundation

/// The Island API lets other apps on this Mac show things in the notch, the way apps share the
/// Dynamic Island on iPhone. Apps send content (text, colors, buttons) over a local HTTP connection and
/// cLockIn draws it in its own style, decides what shows when, and reports button presses back.
public enum IslandAPI {
    public static let version = 1
    public static let defaultPort: UInt16 = 47823
    /// Requests must carry this header. Browsers can't add it to a cross-site request without a CORS
    /// preflight, which the server never approves, so web pages can't post to the notch.
    public static let clientHeader = "x-island-client"
    public static let tokenHeader = "x-island-token"

    /// Where the running server writes its port, so clients don't have to guess.
    public static var discoveryFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("cLockIn", isDirectory: true)
            .appendingPathComponent("island.json")
    }

    static let maxText = 80
    static let maxRows = 30
    static let maxButtons = 3
}

// MARK: Content apps send

public enum IslandPriority: String, Codable, Sendable, Comparable {
    case low, normal, high

    private var rank: Int {
        switch self {
        case .low: 0
        case .normal: 1
        case .high: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public struct IslandButton: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var prominent: Bool?
    /// Opened directly instead of reporting the press back to the app.
    public var url: String?

    public init(id: String, label: String, prominent: Bool? = nil, url: String? = nil) {
        self.id = id
        self.label = label
        self.prominent = prominent
        self.url = url
    }
}

/// Sent once at launch (and again whenever the app wants its token back).
public struct IslandRegistration: Codable, Equatable, Sendable {
    public var app: String
    public var name: String
    public var symbol: String?
    public var tint: String?
    /// http://127.0.0.1:<port>/… that button presses are posted to.
    public var callback: String?

    public init(app: String, name: String, symbol: String? = nil, tint: String? = nil, callback: String? = nil) {
        self.app = app
        self.name = name
        self.symbol = symbol
        self.tint = tint
        self.callback = callback
    }
}

/// The small pill beside the notch. One per app.
public struct IslandActivity: Codable, Equatable, Sendable {
    /// Short text on the right of the notch, like "2d" or "Today".
    public var text: String
    /// Longer description for the menu bar menu, like "BlackRock closes in 2 days".
    public var title: String?
    public var symbol: String?
    public var tint: String?
    /// 0...1 fills a ring; nil shows just the symbol.
    public var progress: Double?
    public var priority: IslandPriority?

    public init(text: String, title: String? = nil, symbol: String? = nil, tint: String? = nil,
                progress: Double? = nil, priority: IslandPriority? = nil) {
        self.text = text
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.progress = progress
        self.priority = priority
    }
}

/// A moment that grows out of the notch, then goes away on its own.
public struct IslandAlert: Codable, Equatable, Sendable {
    public var id: String?
    public var title: String
    public var subtitle: String?
    public var symbol: String?
    public var tint: String?
    public var buttons: [IslandButton]?
    public var sound: Bool?
    /// Seconds before it closes by itself.
    public var duration: Double?

    public init(id: String? = nil, title: String, subtitle: String? = nil, symbol: String? = nil, tint: String? = nil,
                buttons: [IslandButton]? = nil, sound: Bool? = nil, duration: Double? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.buttons = buttons
        self.sound = sound
        self.duration = duration
    }
}

public struct IslandRow: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    /// Short text on the right, like "2d".
    public var detail: String?
    public var symbol: String?
    public var tint: String?
    /// Clicking the row opens this.
    public var url: String?
    public var buttons: [IslandButton]?

    public init(id: String, title: String, subtitle: String? = nil, detail: String? = nil, symbol: String? = nil,
                tint: String? = nil, url: String? = nil, buttons: [IslandButton]? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.symbol = symbol
        self.tint = tint
        self.url = url
        self.buttons = buttons
    }
}

public struct IslandSection: Codable, Equatable, Sendable {
    public var title: String?
    public var rows: [IslandRow]

    public init(title: String? = nil, rows: [IslandRow]) {
        self.title = title
        self.rows = rows
    }
}

/// The app's own tab in the expanded notch.
public struct IslandPanel: Codable, Equatable, Sendable {
    public var title: String
    public var symbol: String?
    public var tint: String?
    public var sections: [IslandSection]
    public var footer: [IslandButton]?
    /// Shown when every section is empty.
    public var emptyText: String?

    public init(title: String, symbol: String? = nil, tint: String? = nil, sections: [IslandSection],
                footer: [IslandButton]? = nil, emptyText: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.sections = sections
        self.footer = footer
        self.emptyText = emptyText
    }
}

/// Posted to the app's callback when someone presses one of its buttons.
public struct IslandEvent: Codable, Equatable, Sendable {
    public var type = "action"
    public var app: String
    /// "alert", "panel" or "footer".
    public var source: String
    /// The alert or row the button belongs to.
    public var target: String?
    public var action: String

    public init(app: String, source: String, target: String?, action: String) {
        self.app = app
        self.source = source
        self.target = target
        self.action = action
    }
}

// MARK: Keeping content to a sensible size

private func clip(_ text: String, _ limit: Int = IslandAPI.maxText) -> String {
    text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
}

public extension IslandActivity {
    var sanitized: IslandActivity {
        var copy = self
        copy.text = clip(text, 10)
        copy.title = title.map { clip($0) }
        copy.progress = progress.map { min(max($0, 0), 1) }
        return copy
    }
}

public extension IslandButton {
    var sanitized: IslandButton {
        var copy = self
        copy.label = clip(label, 18)
        return copy
    }
}

public extension IslandAlert {
    var sanitized: IslandAlert {
        var copy = self
        copy.title = clip(title)
        copy.subtitle = subtitle.map { clip($0, 120) }
        copy.buttons = buttons.map { Array($0.prefix(IslandAPI.maxButtons)).map(\.sanitized) }
        copy.duration = min(max(duration ?? 8, 3), 60)
        return copy
    }
}

public extension IslandPanel {
    var sanitized: IslandPanel {
        var copy = self
        copy.title = clip(title, 24)
        var budget = IslandAPI.maxRows
        copy.sections = sections.map { section in
            let rows = section.rows.prefix(max(budget, 0)).map { row -> IslandRow in
                var row = row
                row.title = clip(row.title)
                row.subtitle = row.subtitle.map { clip($0) }
                row.detail = row.detail.map { clip($0, 12) }
                row.buttons = row.buttons.map { Array($0.prefix(2)).map(\.sanitized) }
                return row
            }
            budget -= rows.count
            return IslandSection(title: section.title.map { clip($0, 40) }, rows: Array(rows))
        }
        copy.footer = footer.map { Array($0.prefix(IslandAPI.maxButtons)).map(\.sanitized) }
        return copy
    }
}

// MARK: Routes

public enum IslandRoute: Equatable, Sendable {
    case status
    case register
    case activity(app: String)
    case alert(app: String)
    case panel(app: String)

    /// `/v1/apps/<app>/activity` and friends. App ids are short and plain: letters, digits, dot, dash.
    public init?(path: String) {
        let parts = path.split(separator: "?", maxSplits: 1)[0].split(separator: "/").map(String.init)
        switch parts {
        case ["v1", "status"]: self = .status
        case ["v1", "register"]: self = .register
        case let p where p.count == 4 && p[0] == "v1" && p[1] == "apps" && IslandRoute.isValidApp(p[2]):
            switch p[3] {
            case "activity": self = .activity(app: p[2])
            case "alert": self = .alert(app: p[2])
            case "panel": self = .panel(app: p[2])
            default: return nil
            }
        default: return nil
        }
    }

    public static func isValidApp(_ app: String) -> Bool {
        guard (1...40).contains(app.count), let first = app.first, first.isASCII, first.isLetter || first.isNumber,
              !app.contains("..") else { return false }
        return app.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }
}

// MARK: A small HTTP/1.1 reader and writer, enough for local JSON requests

public struct IslandHTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    /// Lower-cased names.
    public var headers: [String: String]
    public var body: Data
}

public enum IslandHTTPParseResult: Equatable, Sendable {
    case incomplete
    case invalid(String)
    case request(IslandHTTPRequest)
}

public enum IslandHTTP {
    public static let maxBody = 256 * 1024
    private static let separator = Data("\r\n\r\n".utf8)

    public static func parse(_ data: Data) -> IslandHTTPParseResult {
        guard let end = data.range(of: separator) else {
            return data.count > 16 * 1024 ? .invalid("headers too large") : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else {
            return .invalid("unreadable headers")
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid("bad request line") }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .invalid("bad header") }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxBody else { return .invalid("bad content length") }
        let bodyStart = end.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        let body = data[bodyStart..<(bodyStart + length)]
        return .request(IslandHTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]),
                                          headers: headers, body: Data(body)))
    }

    public static func response(status: Int, body: Data) -> Data {
        let reason = switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    /// Only requests addressed to this machine by name or loopback address; guards against DNS rebinding.
    public static func isLocalHost(_ host: String?, port: UInt16) -> Bool {
        guard let host else { return false }
        return ["127.0.0.1:\(port)", "localhost:\(port)", "[::1]:\(port)"].contains(host.lowercased())
    }
}

// MARK: Colors

public enum IslandColor {
    /// "#ff9f33" or "ff9f33" -> (r, g, b) in 0...1.
    public static func rgb(_ hex: String?) -> (Double, Double, Double)? {
        guard var hex = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255, Double(value & 0xff) / 255)
    }
}
