import Foundation
import XCTest
@testable import TestsAgent

/// The app read the way its code says it: its project, services, work, clients, seams, pages and destinations.
final class ReadTests: XCTestCase {
    private func index(_ change: (String, String) -> String = { _, text in text }) throws -> AppIndex {
        let app = try Fixture.app(change)
        return AppIndex(project: try XCTUnwrap(AppProject.find(in: app)))
    }

    func testTheProjectIsReadByPlutil() throws {
        let app = try Fixture.app()
        let project = try XCTUnwrap(AppProject.find(in: app))
        XCTAssertEqual(project.name, "Supper")
        XCTAssertEqual(project.module, "Supper")
        XCTAssertEqual(project.unitTests?.lastPathComponent, "Tests")
        XCTAssertEqual(project.uiTests?.lastPathComponent, "UITests")
        XCTAssertEqual(project.uiTestTargets, ["SupperUITests-iOS", "SupperUITests-macOS"])
        XCTAssertEqual(project.schemes.map(\.lastPathComponent), ["Supper-iOS.xcscheme", "Supper-macOS.xcscheme"])
        XCTAssertNil(AppProject.find(in: try Fixture.folder()), "an empty folder holds no app")
        XCTAssertEqual(AppProject.identifier("My App-2"), "My_App_2")
    }

    func testAServiceIsReadAsItsCodeSaysIt() throws {
        let index = try index()
        XCTAssertEqual(index.services.map(\.name), ["EnvironmentService", "LayoutService", "RecipesService"])
        let recipes = try XCTUnwrap(index.service(named: "RecipesService"))
        XCTAssertEqual(recipes.relay, "recipes")
        XCTAssertEqual(recipes.fields.map(\.name), ["recipes", "loading", "lastError"])
        XCTAssertEqual(recipes.persistKey, "persistence.Supper.recipes.0001")
        XCTAssertTrue(recipes.hasStatus && recipes.hasClear)
        XCTAssertEqual(recipes.works.map(\.verb), ["load", "more", "favor"])
        XCTAssertEqual(recipes.works.map(\.write), [.replace("recipes"), .append("recipes"), .none])
        XCTAssertEqual(recipes.works.map(\.loadingKey), ["load", "more", "favor"])
        XCTAssertEqual(recipes.works[0].entry.parameters, [SwiftParameter(label: "page", name: "page", type: "Int")])
        XCTAssertEqual(recipes.works[0].entry.returns, "[Recipe]")
        XCTAssertNil(recipes.works[2].entry.returns)
        XCTAssertEqual(index.service(named: "EnvironmentService")?.persistKey, nil, "transient state is not kept")
    }

    func testAWorksOtherKindsAreReadWithTheirOps() throws {
        let environment = try XCTUnwrap(try index().service(named: "EnvironmentService"))
        let boot = try XCTUnwrap(environment.works.first)
        XCTAssertEqual(boot.sets, [SetCall(kind: "booted", arguments: ["isFirstLaunch", "Date()"])])
        XCTAssertEqual(boot.payloadNames["isFirstLaunch"], "isFirstLaunch")
        let booted = try XCTUnwrap(environment.ops.first { $0.kinds == ["booted"] })
        XCTAssertEqual(booted.bindings, ["isFirstLaunch", "date"])
        XCTAssertTrue(booted.assignments.contains(.init(field: "phase", value: ".ready")))
        let layout = try XCTUnwrap(try index().service(named: "LayoutService"))
        XCTAssertEqual(layout.helper("select")?.set, SetCall(kind: "destination", arguments: ["destination"]))
        XCTAssertEqual(layout.helper("closeDetail")?.set, SetCall(kind: "detail", arguments: ["nil"]))
    }

    func testAClientIsReadOffItsPackage() throws {
        let client = try XCTUnwrap(try index().clients.first)
        XCTAssertEqual(client.module, "RecipeKit")
        XCTAssertEqual(client.client, "RecipeClient")
        XCTAssertEqual(client.coding, "RecipeCoding")
        XCTAssertEqual(client.baseURL, "https://api.supper.example")
        XCTAssertEqual(client.endpoints.map(\.name), ["cooks", "favorite", "recipe", "recipes"])
        let recipes = try XCTUnwrap(client.endpoint("recipes"))
        XCTAssertEqual(recipes.method, "GET")
        XCTAssertEqual(recipes.path, "/v1/recipes")
        XCTAssertEqual(recipes.response, "[Recipe]")
        XCTAssertEqual(recipes.pageQuery, "page")
        XCTAssertTrue(recipes.isPaged)
        XCTAssertEqual(client.endpoint("favorite")?.path, "/v1/recipes/{id}/favorite")
        XCTAssertEqual(client.types["Recipe"]?.idType, "Int")
        XCTAssertEqual(client.types["Recipe"]?.hasPreview, true)
        XCTAssertNil(client.mock)
    }

    func testASeamIsFoundAndWhetherATestCanAssignIt() throws {
        let seam = "Shared/Utility/RecipeClient+Current.swift"
        let open = try index()
        XCTAssertEqual(open.seams, [Seam(path: "RecipeClient.current", client: "RecipeClient", isAssignable: true, isInstance: false)])
        XCTAssertTrue(open.reach(open.service(named: "RecipesService")!, open.service(named: "RecipesService")!.works[0]).isMocked)
        let shut = try index { path, text in
            path == seam ? text.replacingOccurrences(of: "nonisolated(unsafe) static var current", with: "static let current") : text
        }
        XCTAssertEqual(shut.seams.first?.isAssignable, false, "a let cannot be assigned")
        let computed = try index { path, text in
            path == seam ? text.replacingOccurrences(of: "nonisolated(unsafe) static var current: RecipeClient = isMocked ? .preview : RecipeClient()",
                                                     with: "static var current: RecipeClient { isMocked ? .preview : RecipeClient() }") : text
        }
        XCTAssertEqual(computed.seams.first?.isAssignable, false, "a computed value with no setter cannot be assigned")
        let set = try index { path, text in
            path == seam ? text.replacingOccurrences(of: "nonisolated(unsafe) static var current: RecipeClient = isMocked ? .preview : RecipeClient()",
                                                     with: "static var current: RecipeClient {\n        get { stored }\n        set { stored = newValue }\n    }\n    nonisolated(unsafe) static var stored = RecipeClient()") : text
        }
        XCTAssertEqual(set.seams.first?.isAssignable, true, "a computed value with a setter can")
        let local = try index { path, text in
            path.hasSuffix("RecipesService.Load.swift") ? text.replacingOccurrences(of: "try await RecipeClient.current.recipes(page: page)",
                                                                                   with: "try await RecipeClient().recipes(page: page)") : text
        }
        let recipes = try XCTUnwrap(local.service(named: "RecipesService"))
        XCTAssertFalse(local.reach(recipes, recipes.works[0]).isMocked, "a client made in the work cannot be mocked")
    }

    func testAPageIsReadWithItsActions() throws {
        let index = try index()
        XCTAssertEqual(index.pages.map(\.name), ["RecipeList", "Settings"])
        let list = try XCTUnwrap(index.pages.first)
        XCTAssertEqual(list.relays, [.init(name: "recipes", service: "RecipesService"), .init(name: "layout", service: "LayoutService")])
        XCTAssertEqual(list.actions.map(\.name), ["refresh", "more", "favor", "browseCooks", "surprise"])
        XCTAssertEqual(list.action("favor")?.parameters.map(\.type), ["Recipe"])
        XCTAssertEqual(list.action("refresh")?.statements, ["try await recipes.load(page: 1)"])
        XCTAssertEqual(list.title, "Recipes")
        XCTAssertEqual(list.imports, ["RecipeKit"])
    }

    func testTheDestinationsAreRead() throws {
        let destinations = try XCTUnwrap(try index().destinations)
        XCTAssertEqual(destinations.cases.map(\.name), ["recipes", "cooks", "settings"])
        XCTAssertEqual(destinations.cases.map(\.title), ["Recipes", "Cooks", "Settings"])
        XCTAssertEqual(destinations.cases.map(\.page), ["RecipeList", "CookList", "Settings"])
        XCTAssertTrue(destinations.opensFromLaunch)
    }

    func testSamplesForWhatATestPasses() {
        let previews: Set<String> = ["Recipe"], enums = ["Course": ["starter", "main"]]
        XCTAssertEqual(Samples.value("Int", name: "page", page: 2, previews: previews, enums: enums), "2")
        XCTAssertEqual(Samples.value("Int?", name: "id", previews: previews, enums: enums), "1")
        XCTAssertEqual(Samples.value("[Recipe]", name: "recipes", previews: previews, enums: enums), "[Recipe.preview]")
        XCTAssertEqual(Samples.value("Course", name: "course", previews: previews, enums: enums), ".starter")
        XCTAssertNil(Samples.value("Pantry", name: "pantry", previews: previews, enums: enums))
        XCTAssertEqual(Samples.element(of: "[Recipe]?"), "Recipe")
        XCTAssertNil(Samples.element(of: "[String: Int]"))
        XCTAssertTrue(Samples.isLiteral(".ready") && Samples.isLiteral("nil") && !Samples.isLiteral("Date()"))
    }

    /// A test passes ids the mock answers and strings its enums are made from (Hearth, 2026-11-01: `postId: 1` found no
    /// comments, and `action: "sample"` was refused by `VoteAction(rawValue:)`).
    func testSamplesUseTheMocksIdsAndTheEnumsAStringMakes() {
        let ids = ["post": "74119", "community": "\"c-12\""]
        XCTAssertEqual(Samples.value("Int", name: "postId", previews: [], enums: [:], mockIDs: ids), "74119")
        XCTAssertEqual(Samples.value("Int", name: "post_id", previews: [], enums: [:], mockIDs: ids), "74119")
        XCTAssertEqual(Samples.value("String", name: "communityID", previews: [], enums: [:], mockIDs: ids), "\"c-12\"")
        XCTAssertEqual(Samples.value("Int", name: "communityID", previews: [], enums: [:], mockIDs: ids), "1", "a quoted id never fills an Int")
        XCTAssertEqual(Samples.value("String", name: "action", previews: [], enums: ["VoteAction": ["up", "down", "none"]],
                                     rawValues: ["action": "VoteAction"]), "\"up\"")
        XCTAssertEqual(Samples.value("String", name: "note", previews: [], enums: [:]), "\"sample\"")
    }
}
