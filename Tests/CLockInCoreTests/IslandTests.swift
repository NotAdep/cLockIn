import XCTest
@testable import CLockInCore

final class IslandTests: XCTestCase {
    private func request(_ text: String) -> IslandHTTPParseResult {
        IslandHTTP.parse(Data(text.utf8))
    }

    func testParsesCompleteRequest() {
        let body = #"{"app":"jobcrack","name":"JobCrack"}"#
        let result = request("POST /v1/register HTTP/1.1\r\nHost: 127.0.0.1:47823\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
        guard case .request(let req) = result else { return XCTFail("expected a request, got \(result)") }
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/v1/register")
        XCTAssertEqual(req.headers["content-type"], "application/json")
        XCTAssertEqual(String(data: req.body, encoding: .utf8), body)
    }

    func testWaitsForTheRestOfTheBody() {
        XCTAssertEqual(request("POST /v1/register HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\""), .incomplete)
        XCTAssertEqual(request("GET /v1/status HTTP/1.1\r\nHost: x"), .incomplete)
    }

    func testRejectsNonsense() {
        guard case .invalid = request("hello\r\n\r\n") else { return XCTFail() }
        guard case .invalid = request("POST / HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n") else { return XCTFail() }
    }

    func testRoutes() {
        XCTAssertEqual(IslandRoute(path: "/v1/status"), .status)
        XCTAssertEqual(IslandRoute(path: "/v1/register"), .register)
        XCTAssertEqual(IslandRoute(path: "/v1/apps/jobcrack/activity"), .activity(app: "jobcrack"))
        XCTAssertEqual(IslandRoute(path: "/v1/apps/com.example.app/panel?x=1"), .panel(app: "com.example.app"))
        XCTAssertEqual(IslandRoute(path: "/v1/apps/jobcrack/alert"), .alert(app: "jobcrack"))
        XCTAssertNil(IslandRoute(path: "/v1/apps/../alert"))
        XCTAssertNil(IslandRoute(path: "/v1/apps/job crack/alert"))
        XCTAssertNil(IslandRoute(path: "/v2/status"))
    }

    func testOnlyLocalHostNames() {
        XCTAssertTrue(IslandHTTP.isLocalHost("127.0.0.1:47823", port: 47823))
        XCTAssertTrue(IslandHTTP.isLocalHost("localhost:47823", port: 47823))
        XCTAssertFalse(IslandHTTP.isLocalHost("evil.example:47823", port: 47823))
        XCTAssertFalse(IslandHTTP.isLocalHost(nil, port: 47823))
    }

    func testDecodesAPanelAndTrimsIt() throws {
        let rows = (0..<40).map { #"{"id":"r\#($0)","title":"Row \#($0)","buttons":[{"id":"a","label":"One"},{"id":"b","label":"Two"},{"id":"c","label":"Three"}]}"# }
        let json = #"{"title":"Jobs with a very long title indeed","sections":[{"title":"Soon","rows":[\#(rows.joined(separator: ","))]}]}"#
        let panel = try JSONDecoder().decode(IslandPanel.self, from: Data(json.utf8)).sanitized
        XCTAssertEqual(panel.sections[0].rows.count, IslandAPI.maxRows)
        XCTAssertEqual(panel.sections[0].rows[0].buttons?.count, 2)
        XCTAssertLessThanOrEqual(panel.title.count, 24)
    }

    func testSanitizesAlertsAndActivities() {
        let alert = IslandAlert(title: "x", buttons: (0..<5).map { IslandButton(id: "\($0)", label: "B") }, duration: 999).sanitized
        XCTAssertEqual(alert.buttons?.count, 3)
        XCTAssertEqual(alert.duration, 60)
        XCTAssertEqual(IslandAlert(title: "x").sanitized.duration, 8)

        let activity = IslandActivity(text: "A very long pill text", progress: 3).sanitized
        XCTAssertEqual(activity.text.count, 10)
        XCTAssertEqual(activity.progress, 1)
    }

    func testPriorityOrder() {
        XCTAssertLessThan(IslandPriority.low, .normal)
        XCTAssertLessThan(IslandPriority.normal, .high)
    }

    func testColors() {
        let rgb = IslandColor.rgb("#ff8000")
        XCTAssertEqual(rgb?.0, 1)
        XCTAssertEqual(rgb?.1 ?? 0, 128.0 / 255, accuracy: 0.001)
        XCTAssertNil(IslandColor.rgb("orange"))
    }

    func testEventEncodes() throws {
        let data = try JSONEncoder().encode(IslandEvent(app: "jobcrack", source: "panel", target: "job-12", action: "shortlist"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["type"] as? String, "action")
        XCTAssertEqual(object?["target"] as? String, "job-12")
    }
}
