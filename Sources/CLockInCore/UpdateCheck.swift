import Foundation

/// A dotted version like "0.3.0" or a tag like "v1.2". Anything after a "-" (e.g. "-beta") is ignored.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[..<dash]) }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    /// Missing parts count as zero, so "1.0" equals "1.0.0".
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// The parts of GitHub's "latest release" response that the update check uses.
public struct GitHubRelease: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public var name: String
        public var browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    public var tagName: String
    public var name: String?
    public var htmlURL: URL
    public var body: String?
    public var draft: Bool
    public var prerelease: Bool
    public var assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body, draft, prerelease, assets
    }
}

public struct AvailableUpdate: Equatable, Sendable {
    public var version: String
    /// The release page, with its notes.
    public var pageURL: URL
    /// The DMG itself, when the release has one.
    public var downloadURL: URL?
    public var notes: String
}

public enum UpdateCheck {
    public static func decodeRelease(from data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// The update to offer, or nil when the release isn't newer than what's running (or isn't a real release).
    public static func availableUpdate(currentVersion: String, release: GitHubRelease) -> AvailableUpdate? {
        guard !release.draft, !release.prerelease,
              let latest = AppVersion(release.tagName),
              let current = AppVersion(currentVersion),
              current < latest else { return nil }
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return AvailableUpdate(
            version: latest.description,
            pageURL: release.htmlURL,
            downloadURL: dmg?.browserDownloadURL,
            notes: release.body ?? ""
        )
    }
}
