import Foundation

public enum TimeFormat {
    /// "4:59", "12:00" or "1:05:00". Rounds up so a timer never shows 0:00 while still running.
    public static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int((interval - 0.001).rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// "45m", "1h 30m" or "2m 30s", for chips and labels.
    public static func short(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let parts = [
            hours > 0 ? "\(hours)h" : nil,
            minutes > 0 ? "\(minutes)m" : nil,
            seconds > 0 ? "\(seconds)s" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }
}

/// Typed duration entry, like the Clock app: digits shift in from the right into HH:MM:SS.
public struct DurationDigits: Equatable, Sendable {
    public static let maxDigits = 6
    public private(set) var digits: String = ""

    public init(digits: String = "") {
        self.digits = String(digits.filter(\.isNumber).suffix(Self.maxDigits))
    }

    public var isEmpty: Bool { digits.isEmpty }

    public mutating func append(_ digit: Character) {
        guard digit.isNumber, digits.count < Self.maxDigits else { return }
        // Leading zeros carry no meaning, so they don't use up space.
        if digits.isEmpty && digit == "0" { return }
        digits.append(digit)
    }

    public mutating func deleteLast() {
        if !digits.isEmpty { digits.removeLast() }
    }

    /// The six HH MM SS digits, zero-padded on the left.
    public var padded: String {
        String(repeating: "0", count: Self.maxDigits - digits.count) + digits
    }

    /// Total seconds; fields over 59 roll over the way the Clock app treats them (90 seconds is 1:30).
    public var duration: TimeInterval {
        let values = Array(padded).map { Int(String($0))! }
        let hours = values[0] * 10 + values[1]
        let minutes = values[2] * 10 + values[3]
        let seconds = values[4] * 10 + values[5]
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }
}

/// Saves Codable state to UserDefaults as JSON.
public struct SnapshotStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
