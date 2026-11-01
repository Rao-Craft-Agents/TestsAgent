import Foundation
import GraniteAgents
import XCTest
@testable import TestsAgent

/// The package as an app finds it: by its record, with the schema a model is shown and the guide a host prompts with.
final class TestsAgentTests: XCTestCase {
    func testTheRecordIsFoundWithNothingListed() throws {
        let tests = try XCTUnwrap(GraniteRoster.discovered().package("tests"), "the record is in this test binary")
        XCTAssertEqual(tests.module, "TestsAgent")
        XCTAssertEqual(tests.summary, TestsAgent.summary)
    }

    func testTheSchemaIsWhatAModelIsShown() {
        let tests = AnyAgentPackage(TestsAgent.self)
        XCTAssertEqual(tests.schema, .object([
            .init(name: "services", schema: .array(.string), required: false),
            .init(name: "pages", schema: .array(.string), required: false),
            .init(name: "ui", schema: .boolean, required: false),
            .init(name: "scenarios", schema: .array(.choice(["normal", "empty", "failing", "slow"])), required: false),
            .init(name: "rounds", schema: .integer, required: false),
            .init(name: "directory", schema: .string, required: false),
        ]))
        XCTAssertTrue(tests.takesDirectory)
        XCTAssertEqual(tests.lanes, 1, "a call edits files other calls share, so calls run one at a time")
        XCTAssertEqual(Set(tests.fields.keys), ["services", "pages", "ui", "scenarios", "rounds"], "a note beside every field the model sees")
        XCTAssertEqual(TestsAgent.word.range(of: #"^[a-z][a-z0-9]{1,31}$"#, options: .regularExpression) != nil, true)
    }

    func testTheGuideTeachesEachMode() {
        let guide = AnyAgentPackage(TestsAgent.self).guide
        for words in ["{}", #"{"services": ["Recipes"], "pages":"#, #""scenarios": ["normal", "failing"]"#, "an empty list tests none", "TestRoot", "-mock YES",
                      "-destination", ".mock()", "RunMode", "never a live server", "iOS simulator"] {
            XCTAssertTrue(guide.contains(words), "the guide says \(words)")
        }
    }

    /// The call as a host makes it: JSON in, the host's folder filled, JSON out naming the files.
    func testACallThroughTheRosterWritesTheFilesItNames() async throws {
        let app = try Fixture.app()
        let input = try JSONSerialization.data(withJSONObject: ["directory": app.path])
        let answer = try await AnyAgentPackage(TestsAgent.self).perform(input, host: AgentHost(directory: app.path, ask: "test the app"))
        let result = try JSONDecoder().decode(TestsResult.self, from: answer)
        XCTAssertEqual(result.services, ["EnvironmentService", "RecipesService"])
        XCTAssertEqual(result.pages, ["RecipeList", "Settings"])
        XCTAssertEqual(result.destinations, ["recipes", "cooks", "settings"])
        XCTAssertEqual(result.path, result.paths.first)
        for path in result.paths {
            XCTAssertTrue(path.hasPrefix(app.path + "/"), path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
        }
        let names = Set(result.paths.map { String($0.dropFirst(app.path.count + 1)) })
        for expected in ["Tests/RecipesServiceTests.swift", "Tests/EnvironmentServiceTests.swift", "Tests/RecipeListPageTests.swift",
                         "Tests/SettingsPageTests.swift", "Tests/Support/TestRoot.swift", "Tests/Support/ServicesOnMocks.swift",
                         "Tests/Support/BackendScenario.swift", "Tests/Support/PageRender.swift", "Tests/Support/RecipeServer.swift",
                         "UITests/SupperDestinationTests.swift", "Shared/Utility/RunMode.swift", "Shared/App.swift",
                         "Services/RecipesService/RecipesService+Center.swift", "Services/LayoutService/LayoutService+Center.swift",
                         "Supper.xcodeproj/xcshareddata/xcschemes/Supper-iOS.xcscheme", "Tests/RecipesOpsTests.swift"] {
            XCTAssertTrue(names.contains(expected), "\(expected) is written: \(names.sorted())")
        }
        XCTAssertFalse(names.contains("Supper.xcodeproj/xcshareddata/xcschemes/Supper-macOS.xcscheme"), "the Mac keeps its UI tests skipped")
        XCTAssertGreaterThan(result.tests, 20)
    }
}

/// A host that names its folder only in `AgentHost`, as one calling over the wire may.
final class HostFolderTests: XCTestCase {
    func testTheHostsFolderIsUsedWhenTheInputHasNone() async throws {
        let app = try Fixture.app()
        let input = try JSONSerialization.data(withJSONObject: ["services": ["Recipes"], "pages": ["Settings"], "ui": false])
        let answer = try await AnyAgentPackage(TestsAgent.self).perform(input, host: AgentHost(directory: app.path))
        let result = try JSONDecoder().decode(TestsResult.self, from: answer)
        XCTAssertEqual(result.services, ["RecipesService"])
        XCTAssertEqual(result.pages, ["Settings"])
        XCTAssertTrue(result.paths.contains(app.appendingPathComponent("Tests/RecipesServiceTests.swift").path), "\(result.paths)")
    }
}
