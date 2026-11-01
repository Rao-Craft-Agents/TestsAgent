import Foundation
import XCTest
@testable import TestsAgent

/// What the tests say: each piece of work in each scenario, the root, the server, the pages, the launches; and
/// nothing written when a call is refused.
final class EmitTests: XCTestCase {
    private func write(_ input: TestsAgent.Input = .init(), change: (String, String) -> String = { _, text in text },
                       model: FakeHostModel? = nil) async throws -> (TestsResult, URL) {
        let app = try Fixture.app(change)
        var input = input
        input.directory = app.path
        return (try await TestsAgent.write(input, model: model, note: { _ in }, yield: { _ in }), app)
    }

    private func tests(in text: String) -> [String] { SwiftText.matches(#"func (\w+)\("#, in: text) }

    func testAServiceTestCoversEachPieceOfWorkInEachScenario() async throws {
        let (_, app) = try await write()
        let text = try Fixture.text(app, "Tests/RecipesServiceTests.swift")
        XCTAssertEqual(tests(in: text), [
            "loadFillsRecipes", "loadAgainReplacesRecipes", "loadWithNothingToShowLeavesRecipesEmpty", "aFailedLoadSaysWhyAndATryAgainClearsIt",
            "loadIsMarkedWhileInFlight", "moreAddsTheNextPageToRecipes", "moreWithNothingLeftKeepsRecipes",
            "aFailedMoreKeepsRecipesAndATryAgainAddsThePage", "moreIsMarkedWhileInFlight", "favorReachesTheBackend",
            "aFailedFavorSaysWhyAndATryAgainClearsIt", "favorIsMarkedWhileInFlight",
        ])
        XCTAssertTrue(text.contains("extension ServicesOnMocks {\n    /// RecipesService's work on mock backend responses"))
        XCTAssertTrue(text.contains("@Suite @MainActor struct RecipesServiceTests {"))
        XCTAssertTrue(text.contains("let value = try await root.recipes.load(page: 1)\n            await root.settle()\n            #expect(!value.isEmpty)\n            #expect(root.recipes.state.recipes == value)"))
        XCTAssertTrue(text.contains("let first = try await root.recipes.load(page: 1)\n            let next = try await root.recipes.more(page: 2)"), "the next page is added to the first")
        XCTAssertTrue(text.contains("#expect(root.recipes.state.recipes == first + next)"))
        XCTAssertTrue(text.contains("#expect(root.recipes.state.recipes == RecipesService.Center.State().recipes)"), "a failure leaves the field as it was")
        XCTAssertTrue(text.contains("root.answer(.normal)"), "a try again after the failure")
        XCTAssertTrue(text.contains("#expect(await root.until { service.state.loading == \"more\" })"))
        XCTAssertTrue(text.contains("#expect(root.recipeServer.received(\"POST\", \"/v1/recipes/{id}/favorite\"))"))
        XCTAssertTrue(text.contains("import RecipeKit\n@testable import Supper"))
    }

    func testAWorkWithNoBackendIsCheckedAgainstItsOps() async throws {
        let (_, app) = try await write()
        let text = try Fixture.text(app, "Tests/EnvironmentServiceTests.swift")
        XCTAssertEqual(tests(in: text), ["bootLeavesItsState"])
        XCTAssertTrue(text.contains("try await root.environment.boot(isFirstLaunch: true)"))
        XCTAssertTrue(text.contains("#expect(root.environment.state.phase == .ready)"))
        XCTAssertTrue(text.contains("#expect(root.environment.state.isFirstLaunch == true)"), "the argument the test passed")
        XCTAssertFalse(text.contains("startedAt"), "a date the work makes itself is not asserted")
    }

    func testScenariosNarrowWhatIsWritten() async throws {
        let (result, app) = try await write(.init(services: ["Recipes"], pages: [], ui: false, scenarios: [.failing]))
        XCTAssertEqual(result.services, ["RecipesService"])
        XCTAssertEqual(result.pages, [], "an empty list draws no page")
        XCTAssertFalse(result.paths.contains { $0.hasSuffix("PageRender.swift") || $0.contains("/UITests/") })
        let names = tests(in: try Fixture.text(app, "Tests/RecipesServiceTests.swift"))
        XCTAssertTrue(names.contains("aFailedLoadSaysWhyAndATryAgainClearsIt") && names.contains("loadFillsRecipes"), "normal is always written")
        XCTAssertFalse(names.contains { $0.contains("NothingToShow") || $0.contains("InFlight") }, "\(names)")
    }

    func testTheRootBootsEveryServiceOnMocks() async throws {
        let (_, app) = try await write()
        let root = try Fixture.text(app, "Tests/Support/TestRoot.swift")
        for line in ["@Relay(.silence) var environment: EnvironmentService", "@Relay(.silence) var layout: LayoutService",
                     "@Relay(.silence) var recipes: RecipesService", "private(set) var recipeServer = RecipeServer(.normal)",
                     "await until(seconds: 5) { self.layout.isLoaded && self.recipes.isLoaded }", "recipes.set(.clear)",
                     "recipeServer = RecipeServer(scenario)", "RecipeClient.current = recipeServer.client",
                     "environment.state.loading == nil && recipes.state.loading == nil", "@testable import Supper"] {
            XCTAssertTrue(root.contains(line), "TestRoot says \(line)")
        }
        let parent = try Fixture.text(app, "Tests/Support/ServicesOnMocks.swift")
        XCTAssertTrue(parent.contains("@Suite(.serialized) @MainActor struct ServicesOnMocks {}"))
    }

    func testTheServerAnswersPagesThenNothingAndNeverTheNetwork() async throws {
        let (_, app) = try await write()
        let server = try Fixture.text(app, "Tests/Support/RecipeServer.swift")
        for line in ["final class RecipeServer: HTTPTransport, @unchecked Sendable {",
                     "RecipeClient(baseURL: URL(string: \"https://api.supper.example\")!, tokens: MemoryTokenStore(), transport: self, retry: .never)",
                     "if method == \"GET\", Self.matches(\"/v1/recipes\", path) {",
                     "return try Self.json(scenario == .empty ? [] : Self.recipesPage(page))",
                     "if method == \"POST\", Self.matches(\"/v1/recipes/{id}/favorite\", path) {", "return try Self.json(Recipe.preview)",
                     "guard (1...3).contains(page) else { return [] }", "item.id = (page - 1) * 2 + index",
                     "HTTPResponse(status: 500", "status: 404", "RecipeCoding.encoder()", "$0.name == \"page\""] {
            XCTAssertTrue(server.contains(line), "the server says \(line)")
        }
        XCTAssertFalse(server.contains("URLSession"), "nothing leaves the process")
    }

    func testAMocksPackageAnswersWhenItHasAMock() async throws {
        let mock = """
        import Foundation

        public enum MockScenario: String, Sendable { case normal, empty, failing, unauthorized, slow }

        extension RecipeClient {
            public static func mock(_ scenario: MockScenario = .normal, latency: Duration = .milliseconds(250)) -> RecipeClient { .preview }
        }
        """
        let app = try Fixture.app()
        try Data(mock.utf8).write(to: app.appendingPathComponent("Packages/RecipeKit/Sources/RecipeKit/Mocks.swift"))
        let result = try await TestsAgent.write(.init(directory: app.path), model: nil, note: { _ in }, yield: { _ in })
        let root = try Fixture.text(app, "Tests/Support/TestRoot.swift")
        XCTAssertTrue(root.contains("case .failing:\n            RecipeClient.current = .mock(.failing, latency: .zero)"), root)
        XCTAssertTrue(root.contains("case .slow:\n            RecipeClient.current = .mock(.slow, latency: .milliseconds(400))"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Tests/Support/RecipeServer.swift").path))
        XCTAssertFalse(try Fixture.text(app, "Tests/RecipesServiceTests.swift").contains("received("), "mocks' requests are its own")
        XCTAssertTrue(result.notes.contains { $0.contains(".mock()") })
    }

    func testPagesAreDrawnInEveryStateAndDriven() async throws {
        let (_, app) = try await write()
        let text = try Fixture.text(app, "Tests/RecipeListPageTests.swift")
        XCTAssertEqual(tests(in: text), ["drawsInLightAndDark", "refreshFillsRecipes", "moreAddsToRecipes", "favorReachesTheBackend",
                                         "browseCooksSetsDestination", "surpriseRuns"])
        XCTAssertTrue(text.contains("@Test(arguments: [BackendScenario.normal, .empty, .failing])"))
        XCTAssertTrue(text.contains("#expect(PageRender.draw(RecipeList(), scheme: .dark) != nil)"))
        XCTAssertTrue(text.contains("let recipe = try #require(root.recipes.state.recipes.first)\n            try await page.favor(recipe: recipe)"))
        XCTAssertTrue(text.contains("#expect(root.recipes.state.recipes.count > beforeRecipes)"))
        XCTAssertTrue(text.contains("#expect(root.layout.state.destination == .settings)\n            #expect(root.layout.state.detail == nil)"),
                      "a helper's set read off the Ops")
        let settings = try Fixture.text(app, "Tests/SettingsPageTests.swift")
        XCTAssertEqual(tests(in: settings), ["drawsInLightAndDark"])
        XCTAssertTrue(settings.contains("/// Settings on mock backend responses: drawn in light and dark."))
    }

    func testUITestsOpenEachDestinationOnMocks() async throws {
        let (_, app) = try await write()
        let text = try Fixture.text(app, "UITests/SupperDestinationTests.swift")
        XCTAssertEqual(tests(in: text), ["setUpWithError", "testRecipesOpensAtLaunch", "testCooksOpensAtLaunch", "testSettingsOpensAtLaunch", "launch", "shows"])
        XCTAssertTrue(text.contains("app.launchArguments += [\"-mock\", \"YES\", \"-destination\", destination]"))
        XCTAssertTrue(text.contains("XCTAssertTrue(shows(\"Recipes\", in: app), \"the app opens on Recipes\")"), "the page's own title")
        XCTAssertTrue(text.contains("XCTAssertTrue(shows(\"Cooks\", in: app)"), "the destination's title when the page is not read")
        XCTAssertTrue(text.contains("app.navigationBars[title].waitForExistence(timeout: 20)"))
        let iOS = try Fixture.text(app, "Supper.xcodeproj/xcshareddata/xcschemes/Supper-iOS.xcscheme")
        XCTAssertFalse(iOS.contains("skipped = \"YES\""), "the simulator runs the UI tests")
        let macOS = try Fixture.text(app, "Supper.xcodeproj/xcshareddata/xcschemes/Supper-macOS.xcscheme")
        XCTAssertTrue(macOS.contains("skipped = \"YES\""), "the Mac keeps them skipped")
    }

    func testAnAppThatNeverReadsMockSaysSo() async throws {
        let (wired, _) = try await write()
        XCTAssertFalse(wired.notes.contains { $0.contains("never reads `-mock`") })
        let (unwired, _) = try await write(change: { path, text in
            path.hasSuffix("RecipeClient+Current.swift") ? text.replacingOccurrences(of: "UserDefaults.standard.bool(forKey: \"mock\") || ProcessInfo.processInfo.environment[\"MOCK\"] == \"1\"", with: "false") : text
        })
        XCTAssertTrue(unwired.notes.contains { $0.hasPrefix("the app never reads `-mock`") }, "\(unwired.notes)")
    }

    func testAnAppWithNoDestinationsLaunchesOnce() async throws {
        let (result, app) = try await write(change: { path, text in path.hasSuffix("AppDestination.swift") ? "import SwiftUI\n" : text })
        XCTAssertEqual(tests(in: try Fixture.text(app, "UITests/SupperDestinationTests.swift")), ["setUpWithError", "testLaunchesOnMocks"])
        XCTAssertTrue(result.notes.contains { $0.contains("no destinations yet") }, "\(result.notes)")
    }

    func testAWorkTheTestsCannotMockIsLeftOutWithANote() async throws {
        let (result, app) = try await write(change: { path, text in
            path.hasSuffix("RecipeClient+Current.swift") ? text.replacingOccurrences(of: "nonisolated(unsafe) static var current", with: "static let current") : text
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Tests/RecipesServiceTests.swift").path))
        XCTAssertTrue(result.notes.contains { $0.contains("RecipesService.load is not tested: `RecipeClient.current` cannot be assigned") }, "\(result.notes)")
        XCTAssertTrue(result.notes.contains { $0.contains("RecipeList.refresh is not tested") }, "\(result.notes)")
        XCTAssertFalse(try Fixture.text(app, "Tests/Support/TestRoot.swift").contains("RecipeClient.current ="), "nothing assigns a let")
    }

    func testEverythingWrittenParses() async throws {
        let (result, _) = try await write()
        let swift = result.paths.filter { $0.hasSuffix(".swift") }.map { URL(fileURLWithPath: $0) }
        XCTAssertNil(try SwiftParse.check(swift))
        XCTAssertEqual(result.tests, 23, "12 RecipesService, 1 EnvironmentService, 6 RecipeList, 1 Settings, 3 launches")
    }

    func testARefusedCallNamesEveryReasonAndWritesNothing() async throws {
        let app = try Fixture.app()
        let before = try Fixture.text(app, "Shared/App.swift")
        do {
            _ = try await TestsAgent.write(.init(services: ["Pantry"], pages: ["Larder"], directory: app.path), model: nil, note: { _ in }, yield: { _ in })
            XCTFail("refused")
        } catch let error as TestsError {
            let text = "\(error)"
            XCTAssertTrue(text.contains("2 problems"), text)
            XCTAssertTrue(text.contains("no service `Pantry`: it has EnvironmentService, LayoutService, RecipesService"), text)
            XCTAssertTrue(text.contains("no page `Larder`: it has RecipeList, Settings"), text)
        }
        XCTAssertEqual(try Fixture.text(app, "Shared/App.swift"), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Tests/Support").path))
        do {
            _ = try await TestsAgent.write(.init(directory: try Fixture.folder().path), model: nil, note: { _ in }, yield: { _ in })
            XCTFail("refused")
        } catch {
            XCTAssertTrue("\(error)".contains("holds no Xcode project"), "\(error)")
        }
        do {
            _ = try await TestsAgent.write(.init(services: ["Layout"], directory: app.path), model: nil, note: { _ in }, yield: { _ in })
            XCTFail("refused")
        } catch {
            XCTAssertTrue("\(error)".contains("LayoutService has no work to test"), "\(error)")
        }
    }

    func testAFileTheAgentDidNotWriteIsNeverOverwritten() async throws {
        let app = try Fixture.app()
        let mine = "import Testing\n\n@Test func recipesByHand() {}\n"
        try Data(mine.utf8).write(to: app.appendingPathComponent("Tests/RecipesServiceTests.swift"))
        do {
            _ = try await TestsAgent.write(.init(directory: app.path), model: nil, note: { _ in }, yield: { _ in })
            XCTFail("refused")
        } catch {
            XCTAssertTrue("\(error)".contains("Tests/RecipesServiceTests.swift is not this agent's"), "\(error)")
        }
        XCTAssertEqual(try Fixture.text(app, "Tests/RecipesServiceTests.swift"), mine)
    }
}
