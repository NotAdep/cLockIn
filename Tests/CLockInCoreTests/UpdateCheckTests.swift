import XCTest
@testable import CLockInCore

final class UpdateCheckTests: XCTestCase {
    private func release(tag: String, draft: Bool = false, prerelease: Bool = false) throws -> GitHubRelease {
        let json = """
        {
          "tag_name": "\(tag)",
          "name": "cLockIn \(tag)",
          "html_url": "https://github.com/NotAdep/cLockIn/releases/tag/\(tag)",
          "body": "- New things",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "published_at": "2026-10-21T12:00:00Z",
          "assets": [
            { "name": "cLockIn-\(tag).dmg.sha256", "browser_download_url": "https://example.com/a.sha256" },
            { "name": "cLockIn-\(tag).dmg", "browser_download_url": "https://example.com/a.dmg" }
          ]
        }
        """
        return try UpdateCheck.decodeRelease(from: Data(json.utf8))
    }

    func testVersionComparison() {
        XCTAssertLessThan(AppVersion("0.9.1")!, AppVersion("0.10.0")!)
        XCTAssertEqual(AppVersion("v1.0")!, AppVersion("1.0.0")!)
        XCTAssertEqual(AppVersion("1.2.0-beta")!.description, "1.2.0")
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1..2"))
    }

    func testNewerReleaseIsOfferedWithItsDMG() throws {
        let update = UpdateCheck.availableUpdate(currentVersion: "0.2.0", release: try release(tag: "v0.3.0"))
        XCTAssertEqual(update?.version, "0.3.0")
        XCTAssertEqual(update?.downloadURL?.absoluteString, "https://example.com/a.dmg")
        XCTAssertEqual(update?.notes, "- New things")
    }

    func testSameOrOlderReleaseIsNotOffered() throws {
        XCTAssertNil(UpdateCheck.availableUpdate(currentVersion: "0.3.0", release: try release(tag: "v0.3.0")))
        XCTAssertNil(UpdateCheck.availableUpdate(currentVersion: "0.4.0", release: try release(tag: "v0.3.0")))
    }

    func testDraftsAndPrereleasesAreIgnored() throws {
        XCTAssertNil(UpdateCheck.availableUpdate(currentVersion: "0.2.0", release: try release(tag: "v0.3.0", draft: true)))
        XCTAssertNil(UpdateCheck.availableUpdate(currentVersion: "0.2.0", release: try release(tag: "v0.3.0", prerelease: true)))
    }
}
