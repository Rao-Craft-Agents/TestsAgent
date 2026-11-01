import Foundation
import XCTest
@testable import TestsAgent

/// The few lines of the app a test run needs, each made once.
final class EditTests: XCTestCase {
    private func write(_ app: URL) async throws -> TestsResult {
        try await TestsAgent.write(.init(directory: app.path), model: nil, note: { _ in }, yield: { _ in })
    }

    func testTheAppShowsNoPageWhileItHostsItsTests() async throws {
        let app = try Fixture.app()
        _ = try await write(app)
        let text = try Fixture.text(app, "Shared/App.swift")
        XCTAssertTrue(text.contains("        WindowGroup {\n            if RunMode.showsPages {\n                Home()\n            }\n        }"), text)
        let mode = try Fixture.text(app, "Shared/Utility/RunMode.swift")
        XCTAssertTrue(mode.contains("environment[\"XCTestBundlePath\"] != nil"))
        XCTAssertTrue(mode.contains("UserDefaults.standard.bool(forKey: \"mock\")"))
    }

    func testPersistedStoresAreKeyedApartUnderTestsAndMocks() async throws {
        let app = try Fixture.app()
        _ = try await write(app)
        XCTAssertTrue(try Fixture.text(app, "Services/RecipesService/RecipesService+Center.swift")
            .contains("@Store(persist: \"persistence.Supper.recipes.0001\" + RunMode.storeSuffix, autoSave: true, preload: true)"))
        XCTAssertTrue(try Fixture.text(app, "Services/LayoutService/LayoutService+Center.swift").contains("+ RunMode.storeSuffix"))
        XCTAssertFalse(try Fixture.text(app, "Services/EnvironmentService/EnvironmentService+Center.swift").contains("RunMode"))
    }

    func testEveryUITestLaunchesOnMocks() async throws {
        let app = try Fixture.app()
        let result = try await write(app)
        XCTAssertTrue(try Fixture.text(app, "UITests/SupperUITests.swift").contains("app.launchArguments += [\"-mock\", \"YES\"]\n        app.launch()"))
        XCTAssertTrue(result.notes.contains("UITests/SupperUITests.swift launches the app on mock backend responses too"), "\(result.notes)")
    }

    func testAForgottenPackageImportIsAdded() async throws {
        let app = try Fixture.app()
        let result = try await write(app)
        let text = try Fixture.text(app, "Tests/RecipesOpsTests.swift")
        XCTAssertTrue(text.contains("import Testing\nimport RecipeKit\n@testable import Supper"), text)
        XCTAssertTrue(result.notes.contains { $0.contains("Tests/RecipesOpsTests.swift names a package's types") })
    }

    func testASecondCallMakesNoEditTwice() async throws {
        let app = try Fixture.app()
        _ = try await write(app)
        let snapshot = try ["Shared/App.swift", "Services/RecipesService/RecipesService+Center.swift", "Tests/RecipesOpsTests.swift",
                            "Tests/RecipesServiceTests.swift", "Supper.xcodeproj/xcshareddata/xcschemes/Supper-iOS.xcscheme", "UITests/SupperUITests.swift"]
            .map { try Fixture.text(app, $0) }
        let second = try await write(app)
        let again = try ["Shared/App.swift", "Services/RecipesService/RecipesService+Center.swift", "Tests/RecipesOpsTests.swift",
                         "Tests/RecipesServiceTests.swift", "Supper.xcodeproj/xcshareddata/xcschemes/Supper-iOS.xcscheme", "UITests/SupperUITests.swift"]
            .map { try Fixture.text(app, $0) }
        XCTAssertEqual(snapshot, again)
        let edited = second.paths.map { String($0.dropFirst(app.path.count + 1)) }
        for path in ["Shared/App.swift", "Services/RecipesService/RecipesService+Center.swift", "Tests/RecipesOpsTests.swift",
                     "Supper.xcodeproj/xcshareddata/xcschemes/Supper-iOS.xcscheme", "Shared/Utility/RunMode.swift", "UITests/SupperUITests.swift"] {
            XCTAssertFalse(edited.contains(path), "\(path) is not edited twice")
        }
        XCTAssertTrue(edited.contains("Tests/RecipesServiceTests.swift"), "the tests are written again from the code as it is")
    }

    func testTheEditsOnTheirOwn() {
        let app = "struct A: App {\n    var body: some Scene {\n        WindowGroup {\n            Root()\n                .tint(.red)\n        }\n    }\n}\n"
        let guarded = AppEdits.guardedApp(app)
        XCTAssertEqual(guarded, "struct A: App {\n    var body: some Scene {\n        WindowGroup {\n            if RunMode.showsPages {\n                Root()\n                    .tint(.red)\n            }\n        }\n    }\n}\n")
        XCTAssertNil(AppEdits.guardedApp(guarded ?? ""), "once")
        let center = "@Store(persist: \"k.0001\", autoSave: true) var state: State"
        let keyed = AppEdits.keyedStore(center)
        XCTAssertEqual(keyed, "@Store(persist: \"k.0001\" + RunMode.storeSuffix, autoSave: true) var state: State")
        XCTAssertNil(AppEdits.keyedStore(keyed ?? ""), "once")
        XCTAssertNil(AppEdits.keyedStore("@Store var state: State"), "a transient store keeps nothing")
        let scheme = "<TestableReference\n skipped = \"YES\">\n<BuildableReference BlueprintName = \"AUITests-iOS\"/>\n</TestableReference>"
        XCTAssertEqual(AppEdits.runningUITests(scheme, targets: ["AUITests-iOS"])?.contains("skipped = \"NO\""), true)
        XCTAssertNil(AppEdits.runningUITests(scheme, targets: ["Other"]))
        let running = scheme.replacingOccurrences(of: "\"YES\"", with: "\"NO\"").replacingOccurrences(of: "iOS", with: "macOS")
        XCTAssertEqual(AppEdits.runningUITests(running, targets: ["AUITests-macOS"], run: false)?.contains("skipped = \"YES\""), true,
                       "a Mac scheme keeps its UI tests skipped")
        let launch = "    func testLaunches() throws {\n        let app = XCUIApplication()\n        app.launch()\n    }"
        XCTAssertEqual(AppEdits.launchingOnMocks(launch),
                       "    func testLaunches() throws {\n        let app = XCUIApplication()\n        app.launchArguments += [\"-mock\", \"YES\"]\n        app.launch()\n    }")
        XCTAssertNil(AppEdits.launchingOnMocks(AppEdits.launchingOnMocks(launch) ?? ""), "once")
    }
}
