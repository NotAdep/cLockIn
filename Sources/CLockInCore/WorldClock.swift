import Foundation

public struct WorldClockCity: Codable, Identifiable, Equatable, Hashable, Sendable {
    /// The time zone identifier, e.g. "Asia/Kolkata".
    public var id: String
    public var name: String

    public init(timeZoneIdentifier: String, name: String? = nil) {
        id = timeZoneIdentifier
        self.name = name ?? WorldClock.cityName(for: timeZoneIdentifier)
    }

    public var timeZone: TimeZone { TimeZone(identifier: id) ?? .current }
}

public enum WorldClock {
    public static let defaultCities: [WorldClockCity] = [
        "America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Tokyo",
    ].map { WorldClockCity(timeZoneIdentifier: $0) }

    /// Time zone database names that use an older spelling of the city.
    private static let modernNames = [
        "Calcutta": "Kolkata", "Saigon": "Ho Chi Minh City", "Katmandu": "Kathmandu",
        "Rangoon": "Yangon", "Kiev": "Kyiv", "Godthab": "Nuuk", "Ulan Bator": "Ulaanbaatar",
    ]

    /// "Asia/Kolkata" → "Kolkata", "America/Port_of_Spain" → "Port of Spain", "Asia/Calcutta" → "Kolkata".
    public static func cityName(for identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        let name = last.replacingOccurrences(of: "_", with: " ")
        return modernNames[name] ?? name
    }

    /// Every city-level time zone, for searching.
    public static var allCities: [WorldClockCity] {
        TimeZone.knownTimeZoneIdentifiers
            .filter { $0.contains("/") && !$0.hasPrefix("Etc/") }
            .map { WorldClockCity(timeZoneIdentifier: $0) }
            .sorted { $0.name < $1.name }
    }

    public static func search(_ query: String, in cities: [WorldClockCity] = allCities) -> [WorldClockCity] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return cities }
        return cities.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// How a city's clock relates to the local one, like the Clock app: "Today, +5:30", "Tomorrow, +9h",
    /// "Yesterday, −3h", or "Today, same time".
    public static func relation(
        of other: TimeZone,
        to local: TimeZone = .current,
        at date: Date = Date(),
        calendar baseCalendar: Calendar = .current
    ) -> String {
        let difference = other.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)

        var localCalendar = baseCalendar
        localCalendar.timeZone = local
        var otherCalendar = baseCalendar
        otherCalendar.timeZone = other
        let localDay = localCalendar.dateComponents([.year, .month, .day], from: date)
        let otherDay = otherCalendar.dateComponents([.year, .month, .day], from: date)
        let dayShift = localCalendar.dateComponents(
            [.day],
            from: localCalendar.date(from: localDay)!,
            to: localCalendar.date(from: otherDay)!
        ).day ?? 0

        let day = switch dayShift {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: dayShift > 0 ? "+\(dayShift) days" : "\(dayShift) days"
        }
        guard difference != 0 else { return "\(day), same time" }

        let sign = difference > 0 ? "+" : "−"
        let hours = abs(difference) / 3600
        let minutes = (abs(difference) % 3600) / 60
        let amount = minutes == 0 ? "\(hours)h" : "\(hours):\(String(format: "%02d", minutes))"
        return "\(day), \(sign)\(amount)"
    }

    /// True between 6 AM and 6 PM in that time zone, for light and dark clock faces.
    public static func isDaytime(in zone: TimeZone, at date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)
        return (6..<18).contains(hour)
    }
}
