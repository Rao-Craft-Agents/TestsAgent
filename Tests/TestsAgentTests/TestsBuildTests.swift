import Foundation
import XCTest
@testable import TestsAgent

/// The tests written for a real app, run for real: an app made call by call through the family's installed runners
/// (granite's project, network's client package, two services whose work calls the client, two list pages and a
/// settings page, navigation with three destinations) and its mock wiring; the tests agent run on it; then the
/// service and page tests run by `xcodebuild test` on the Mac, the same and the UI launch tests on the iOS
/// simulator, and a copy with a broken reducer that a test catches. Gated (`TESTS_BUILD=1`): builds take minutes.
final class TestsBuildTests: XCTestCase {
    let simulator = ProcessInfo.processInfo.environment["TESTS_SIMULATOR"] ?? "iPhone 18 Pro"

    func testTheWrittenTestsRunAndPassAndCatchABrokenReducer() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TESTS_BUILD"] == "1", "set TESTS_BUILD=1 to build and run the tests")
        let work = try Fixture.folder()
        let app = work.appendingPathComponent("Trailhead")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Self.makeApp(app, logs: work)
        let started = Date()
        let result = try await TestsAgent.write(.init(directory: app.path), model: nil, note: { _ in }, yield: { _ in })
        Self.say("tests wrote \(result.paths.count) files, \(result.tests) tests, in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        XCTAssertEqual(result.services, ["EnvironmentService", "HutsService", "TrailsService"])
        XCTAssertEqual(result.pages, ["Home", "HutList", "Settings", "TrailList"])
        XCTAssertEqual(result.destinations, ["trails", "huts", "settings"])

        // The Mac: the service and page tests run and pass; the UI tests stay skipped.
        let mac = try Shell.run("xcodebuild", ["-scheme", "Trailhead-macOS", "-destination", "platform=macOS",
                                               "-derivedDataPath", work.appendingPathComponent("dd-mac").path, "test"],
                                in: app, log: work.appendingPathComponent("mac.log"))
        XCTAssertEqual(mac.status, 0, "the Mac's tests pass (\(work.path)/mac.log):\n\(mac.tail())")
        for suite in ["TrailsServiceTests", "HutsServiceTests", "EnvironmentServiceTests", "TrailListPageTests", "HutListPageTests", "SettingsPageTests", "ServicesOnMocks"] {
            XCTAssertTrue(mac.log.contains("Suite \(suite) passed"), "\(suite) ran and passed on the Mac")
        }
        let macTotal = Self.total(mac.log)
        Self.say("macOS: \(macTotal ?? "no total")")

        // What a test run kept: only its own stores, beside where a person's would be.
        let stores = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/nyc.rao.trailhead/Data/Library/Application Support/nyc.rao.trailhead/granite-db")
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: stores.path)) ?? []
        XCTAssertTrue(kept.contains("persistence.Trailhead.trails.0001.tests"), "the tests kept their own store: \(kept)")
        XCTAssertFalse(kept.contains("persistence.Trailhead.trails.0001"), "and never a person's: \(kept)")

        // The simulator: the same tests, and a launch a destination.
        let iOS = try Shell.run("xcodebuild", ["-scheme", "Trailhead-iOS", "-destination", "platform=iOS Simulator,name=\(simulator)",
                                               "-derivedDataPath", work.appendingPathComponent("dd-ios").path, "test"],
                                in: app, log: work.appendingPathComponent("ios.log"))
        XCTAssertEqual(iOS.status, 0, "the simulator's tests pass (\(work.path)/ios.log):\n\(iOS.tail())")
        for destination in ["Trails", "Huts", "Settings"] {
            XCTAssertTrue(iOS.log.contains("-[TrailheadUITests.TrailheadDestinationTests test\(destination)OpensAtLaunch]' passed"),
                          "the \(destination) launch test ran and passed on the simulator")
        }
        Self.say("iOS: \(Self.total(iOS.log) ?? "no total"); UI: \(iOS.log.components(separatedBy: "TrailheadDestinationTests test").count - 1) launch lines")

        // A copy whose load-more replaces the list instead of adding to it: the test of that work fails, and says why.
        let broken = work.appendingPathComponent("Broken")
        try FileManager.default.copyItem(at: app, to: broken)
        let reducer = broken.appendingPathComponent("Services/TrailsService/Reducers/TrailsService.More.swift")
        let text = try String(contentsOf: reducer, encoding: .utf8)
        XCTAssertTrue(text.contains("service.set(.appendTrails(value))"))
        try Data(text.replacingOccurrences(of: "service.set(.appendTrails(value))", with: "service.set(.trails(value))").utf8).write(to: reducer)
        let caught = try Shell.run("xcodebuild", ["-scheme", "Trailhead-macOS", "-destination", "platform=macOS",
                                                  "-derivedDataPath", work.appendingPathComponent("dd-broken").path, "test"],
                                   in: broken, log: work.appendingPathComponent("broken.log"))
        XCTAssertNotEqual(caught.status, 0, "a broken reducer fails the tests")
        let failures = caught.log.split(separator: "\n").filter { $0.contains("recorded an issue") }.map(String.init)
        XCTAssertTrue(failures.contains { $0.contains("moreAddsTheNextPageToTrails") && $0.contains("first + next") },
                      "the test of the load-more work fails on what it should have added:\n\(failures.joined(separator: "\n"))")
        XCTAssertFalse(failures.contains { $0.contains("loadFillsTrails") }, "and the work that is right still passes")
        Self.say("broken reducer: \(failures.count) issues, first: \(failures.first ?? "none")")

        try Self.cleanUp(simulator: simulator, work: work)
    }

    /// The app as Craft's turns would make it: each layer by its agent's runner, and the glue the turn's model writes.
    static func makeApp(_ app: URL, logs: URL) throws {
        func granite(_ input: [String: Any], _ step: String) throws {
            try Runners.call("GraniteAgent", "granite", input, in: app, log: logs.appendingPathComponent("\(step).ndjson"))
        }
        try granite(["make": "project", "name": "Trailhead", "bundleId": "nyc.rao.trailhead"], "1-project")
        try Runners.call("NetworkAgent", "network", [
            "name": "TrailKit", "baseURL": "https://api.trailhead.example", "coding": "snake",
            "endpoints": [
                "GET /v1/trails?page,per_page -> [Trail] as trails paged \"the trails near you, nearest first\"",
                "GET /v1/trails/{id:Int} -> Trail as trail",
                "POST /v1/trails/{id:Int}/save -> Trail as saveTrail \"keeps a trail for later\"",
                "GET /v1/huts?page -> [Hut] as huts paged",
            ],
            "entities": [
                "Trail \"a trail someone can hike\": id Int, name String, miles Double = 1.5, climb Int = 0, hut Hut?, saved Bool = false",
                "Hut \"a mountain hut on a trail\": id Int, name String, beds Int = 0",
            ],
        ], in: app, log: logs.appendingPathComponent("2-network.ndjson"))
        // The glue the turn's model writes: the one client the services send through, the preview's answers on mocks.
        try Data("""
            import Foundation
            import TrailKit

            extension TrailClient {
                /// The client the app's services send through: the live API, or the preview's sample answers when the app runs
                /// on mocks (`-mock YES` or `MOCK=1`), so its screens, tests and screenshots need no server.
                nonisolated(unsafe) static var current: TrailClient = isMocked ? .preview : TrailClient()

                /// Whether the app runs on mock backend responses.
                static var isMocked: Bool {
                    UserDefaults.standard.bool(forKey: "mock") || ProcessInfo.processInfo.environment["MOCK"] == "1"
                }
            }

            """.utf8).write(to: app.appendingPathComponent("Shared/Utility/TrailClient+Current.swift"))
        try granite(["make": "service", "type": "Trails", "state": ["trails [Trail] = []"], "persist": true,
                     "events": ["load(page Int) -> trails = TrailClient.current.trails(page: page) \"loads a page of trails, nearest first\"",
                                "more(page Int) +> trails = TrailClient.current.trails(page: page) \"adds the next page\"",
                                "save(id Int) = TrailClient.current.saveTrail(id: id) \"keeps a trail for later\""],
                     "notes": "The trails near the hiker, nearest first, kept between launches."], "3-trails")
        try granite(["make": "service", "type": "Huts", "state": ["huts [Hut] = []"],
                     "events": ["load(page Int) -> huts = TrailClient.current.huts(page: page) \"loads a page of huts\""],
                     "notes": "The mountain huts along the trails."], "4-huts")
        try granite(["make": "component", "type": "TrailList", "layout": "list", "relays": ["trails: TrailsService"],
                     "shows": ["items = trails.state.trails", "title = \"Trails\"", "empty = \"No trails yet\""],
                     "actions": ["refresh = try await trails.load(page: 1)", "more = try await trails.more(page: trails.state.trails.count / 20 + 2)",
                                 "save(trail Trail) \"Save\" bookmark = try await trails.save(id: trail.id)"]], "5-trail-list")
        try granite(["make": "component", "type": "HutList", "layout": "list", "relays": ["huts: HutsService"],
                     "shows": ["items = huts.state.huts", "title = \"Huts\"", "empty = \"No huts yet\""],
                     "actions": ["refresh = try await huts.load(page: 1)"]], "6-hut-list")
        try granite(["make": "component", "type": "Settings", "layout": "settings", "relays": ["config: ConfigService"],
                     "shows": ["\"Appearance/Theme\" = config.state.appearance", "title = \"Settings\""]], "7-settings")
        try granite(["make": "navigation", "style": "adaptive",
                     "destinations": ["trails: TrailList \"Trails\" map", "huts: HutList \"Huts\" house", "settings: Settings \"Settings\" gearshape"]],
                    "8-navigation")
        // GraniteAgent dee2792 writes a row view that names the package's type without importing the package when no
        // action of its page names the type (HutList); the turn's build fails there and its model adds the import.
        for row in try FileManager.default.subpathsOfDirectory(atPath: app.appendingPathComponent("Components").path) where row.hasSuffix("View.swift") {
            let url = app.appendingPathComponent("Components").appendingPathComponent(row)
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.range(of: #"\b(Trail|Hut)\b"#, options: .regularExpression) != nil, !text.contains("import TrailKit") {
                try Data(text.replacingOccurrences(of: "import SwiftUI\n", with: "import SwiftUI\nimport TrailKit\n").utf8).write(to: url)
            }
        }
    }

    /// The run's apps taken off the simulator and the Mac's container, and the build folders removed.
    static func cleanUp(simulator: String, work: URL) throws {
        let list = try Shell.run("xcrun", ["simctl", "list", "devices", "available", "-j"], in: work, log: work.appendingPathComponent("devices.json"))
        let devices = ((try? JSONSerialization.jsonObject(with: Data(list.log.utf8))) as? [String: Any])?["devices"] as? [String: [[String: Any]]] ?? [:]
        let udid = devices.values.flatMap { $0 }.first { $0["name"] as? String == simulator && $0["state"] as? String == "Booted" }?["udid"] as? String
        for bundle in ["nyc.rao.trailhead", "nyc.rao.trailhead.uitests.xctrunner"] where udid != nil {
            _ = try? Shell.run("xcrun", ["simctl", "uninstall", udid!, bundle], in: work, log: work.appendingPathComponent("uninstall.log"))
        }
        // The container itself is the system's to remove; what the run kept in it is not.
        let container = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/nyc.rao.trailhead/Data")
        try? FileManager.default.removeItem(at: container)
        for build in ["dd-mac", "dd-ios", "dd-broken"] { try? FileManager.default.removeItem(at: work.appendingPathComponent(build)) }
    }

    /// `Test run with N tests in M suites passed after S seconds.`
    static func total(_ log: String) -> String? {
        log.split(separator: "\n").last { $0.contains("Test run with") }.map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    static func say(_ line: String) { FileHandle.standardError.write(Data("TESTS_BUILD \(line)\n".utf8)) }
}
