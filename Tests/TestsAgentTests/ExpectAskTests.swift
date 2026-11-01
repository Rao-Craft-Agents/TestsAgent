import Foundation
import XCTest
@testable import TestsAgent

/// What a page action leaves when its code does not say: asked of the host's model, checked, parsed, asked again.
final class ExpectAskTests: XCTestCase {
    func testAnUndeterminedActionIsAskedAndCheckedBeforeItLands() async throws {
        let app = try Fixture.app()
        let model = FakeHostModel([
            #"{"expectations": ["root.layout.state.detail = \"1\""]}"#,
            #"{"expectations": ["root.layout.state.panel != nil"]}"#,
            #"{"expectations": ["root.layout.state.detail != nil", "root.recipes.state.lastError == nil"]}"#,
        ])
        let frames = Frames()
        let result = try await TestsAgent.write(.init(pages: ["RecipeList"], ui: false, directory: app.path), model: model, note: { _ in }) { frame in
            if case .asked(let page, let action, let rounds) = frame { frames.add("\(page).\(action) \(rounds)") }
        }
        XCTAssertEqual(frames.all, ["RecipeList.surprise 3"])
        XCTAssertEqual(model.asked.count, 3, "browseCooks is read off the code; only surprise is asked")
        XCTAssertTrue(model.asked[1].user.contains("What was wrong with it:\n- `root.layout.state.detail = \"1\"` assigns"), model.asked[1].user)
        XCTAssertTrue(model.asked[2].user.contains("LayoutService's state has no `panel`"), model.asked[2].user)
        let text = try Fixture.text(app, "Tests/RecipeListPageTests.swift")
        XCTAssertTrue(text.contains("try await page.surprise()\n            await root.settle()\n            #expect(root.recipes.state.lastError == nil)\n            #expect(root.layout.state.detail != nil)"), text)
        XCTAssertFalse(result.notes.contains { $0.contains("surprise") }, "\(result.notes)")
    }

    func testThePromptNamesWhatTheTestHasAndComesFromAnotherApp() async throws {
        let app = try Fixture.app()
        let model = FakeHostModel([#"{"expectations": ["root.layout.state.detail != nil"]}"#])
        _ = try await TestsAgent.write(.init(pages: ["RecipeList"], ui: false, directory: app.path), model: model, note: { _ in }, yield: { _ in })
        let ask = try XCTUnwrap(model.asked.first)
        XCTAssertTrue(ask.user.contains("The page RecipeList, the action:\nfunc surprise() async throws {"))
        XCTAssertTrue(ask.user.contains("- root.layout (LayoutService), the page's `layout`: destination AppDestination"), ask.user)
        XCTAssertTrue(ask.user.contains("- root.recipes (RecipesService), the page's `recipes`: recipes [Recipe]"))
        XCTAssertTrue(ask.user.contains("load(page: Int) replaces recipes"))
        XCTAssertTrue(ask.system.contains("Answer as JSON: {\"expectations\": [\"…\"]}"))
    }

    func testAnAnswerThatNeverComesRightIsLeftOut() async throws {
        let app = try Fixture.app()
        let model = FakeHostModel([#"{"expectations": ["try await root.layout.reload()"]}"#])
        let result = try await TestsAgent.write(.init(pages: ["RecipeList"], ui: false, rounds: 2, directory: app.path), model: model,
                                                note: { _ in }, yield: { _ in })
        XCTAssertEqual(model.asked.count, 2)
        XCTAssertTrue(result.notes.contains("RecipeList.surprise: what it leaves did not come right in 2 rounds, so its test checks only that it ends without a failure"),
                      "\(result.notes)")
        let text = try Fixture.text(app, "Tests/RecipeListPageTests.swift")
        XCTAssertFalse(text.contains("reload"), "a wrong answer never lands")
    }

    func testWithNoModelTheNoteSaysSo() async throws {
        let app = try Fixture.app()
        let result = try await TestsAgent.write(.init(pages: ["RecipeList"], ui: false, directory: app.path), model: nil, note: { _ in }, yield: { _ in })
        XCTAssertTrue(result.notes.contains { $0.hasPrefix("RecipeList.surprise's test checks only that it ends without a failure") && $0.contains("no model to ask") },
                      "\(result.notes)")
    }

    func testTheChecksOnTheirOwn() throws {
        let page = try XCTUnwrap(AppIndex(project: try XCTUnwrap(AppProject.find(in: try Fixture.app()))).pages.first)
        let plan = try XCTUnwrap(PageTestsEmitter(page: page, index: AppIndex(project: AppProject.find(in: try Fixture.app())!), scenarios: [.normal], backends: [])
            .plans().first { $0.action.name == "favor" })
        let index = AppIndex(project: try XCTUnwrap(AppProject.find(in: try Fixture.app())))
        XCTAssertEqual(ExpectAsk.check(["root.recipes.state.recipes.contains { $0.id == recipe.id }"], plan: plan, index: index), [])
        XCTAssertEqual(ExpectAsk.check(["recipe.favorite == false"], plan: plan, index: index), [], "an argument may be checked")
        XCTAssertFalse(ExpectAsk.check(["root.pantry.state.items.isEmpty"], plan: plan, index: index).isEmpty)
        XCTAssertFalse(ExpectAsk.check(["root.recipes.state.recipes.isEmpty ==="], plan: plan, index: index).isEmpty, "does not parse")
        XCTAssertFalse(ExpectAsk.check(["true"], plan: plan, index: index).isEmpty, "checks nothing")
    }
}
