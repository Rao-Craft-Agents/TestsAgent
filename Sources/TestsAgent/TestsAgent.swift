//  WHAT: Functional tests for an app built on Granite, as a Granite agent package: each service's work called
//        through its ticketed entry with the backend mocked and the state it leaves asserted, each page drawn
//        offscreen in light and dark and its actions run, a UI launch test per destination, and the root that boots
//        the app's services on mocks. Never a live server.
//  IN:   Input: the services and pages to test (all when left out), whether to write the UI tests, the backend's
//        scenarios, the model's rounds.
//  OUT:  TestsResult: the files written or edited, what they test, how many tests, and what was left out and why.
//  PIN:  THE CODE IS THE SPEC. What a test calls and asserts is read off the app's services, reducers, Ops, pages
//        and destinations; the host's model is asked only what a page action leaves when its code does not say,
//        and its answer is checked and parsed before it lands.
//  PIN:  NOTHING WRITTEN UNTIL EVERYTHING IS RIGHT. A call that cannot be honoured is refused with every reason at
//        once; every file is staged and parsed, then moved into the project together.
//  PIN:  ONE CALL AT A TIME (`lanes` 1). A call edits files other calls share (the app's `App`, its centers, its
//        schemes) and writes the whole test layer from the code as it is, so a second call waits for the first.

import Foundation
import GraniteAgents

public struct TestsAgent: GraniteAgentPackage {
    public struct Input: Codable, Sendable {
        /// The services whose work is tested: `Recipes` or `RecipesService`; every service with work when left out,
        /// none when empty.
        public var services: [String]?
        /// The pages drawn and driven: `RecipeList`; every page when left out, none when empty.
        public var pages: [String]?
        /// Whether to write a UI launch test for each destination; true when left out.
        public var ui: Bool?
        /// What the mock backend answers in the service tests; all four when left out.
        public var scenarios: [TestsScenario]?
        /// How many times the host's model may answer what one page action leaves; 3 when left out.
        public var rounds: Int?
        /// The host's folder.
        public var directory: String?

        public init(services: [String]? = nil, pages: [String]? = nil, ui: Bool? = nil, scenarios: [TestsScenario]? = nil,
                    rounds: Int? = nil, directory: String? = nil) {
            self.services = services; self.pages = pages; self.ui = ui; self.scenarios = scenarios; self.rounds = rounds
            self.directory = directory
        }
    }

    public typealias Event = TestsFrame
    public typealias Output = TestsResult
    public typealias Compute = Void

    public static let word = "tests"
    public static let lanes: Int? = 1
    public static let summary = "writes functional tests for an app built on Granite — each service's work on mock backend responses, each page drawn in light and dark with its actions run, and a launch test per destination — never against a live server."
    public static let fields = [
        "services": "the services whose work is tested, `Recipes` or `RecipesService`; every service with work when left out, none for []",
        "pages": "the pages drawn in light and dark and driven through their actions, `RecipeList`; every page when left out, none for []",
        "ui": "whether to write a UI launch test per destination, run on the iOS simulator; true when left out",
        "scenarios": "what the mock backend answers in the service tests: normal (pages of items), empty, failing (a server error, then a try again), slow (work seen in flight); all four when left out",
        "rounds": "how many answers the host's model may give for what one page action leaves, when its code does not say; 3 when left out",
    ]
    public static let guide = #"""
        Tag tests once an app's services, pages and navigation exist (granite made them), to prove the app works on mock backend responses, never a live server. One call writes the whole layer from the code: Tests/Support/TestRoot.swift (a relay to every service, booted on mocks before each test; each suite nested under one serialized parent), a test file a service (each piece of work called through its ticketed entry: the field it fills or adds the next page to, loading cleared, lastError set when the backend fails and cleared by a try again, nothing added past the last page, the work marked while in flight), a test file a page (drawn offscreen in light and dark, loaded, empty and failing; each +Actions function run with the state it leaves), and UITests/<App>DestinationTests.swift (one launch a destination with -mock YES -destination <case>, run on the iOS simulator; the macOS scheme keeps UI tests skipped). The backend is the client's .mock() when the mocks agent wrote one, else a server the tests play from the network package's preview values; a service's work must send through a value the tests can assign, like `RecipeClient.current`. The app gains RunMode: while it hosts its unit tests it shows no pages, and a persisted store's key gains .tests (or .mock on a mock launch), so tests never touch what a person saved.

        everything: {} tests every service with work, every page and every destination.

        some: {"services": ["Recipes"], "pages": ["RecipeList", "RecipeDetail"], "ui": false} tests RecipesService's work and those two pages, and writes no UI tests.

        scenarios: {"services": ["Recipes"], "pages": [], "ui": false, "scenarios": ["normal", "failing"]} tests only RecipesService, on loaded and failing backends (empty and slow left out); an empty list tests none of its kind.

        Run them with `xcodebuild -scheme <App>-macOS -destination platform=macOS test` (service and page tests) and `xcodebuild -scheme <App>-iOS -destination 'platform=iOS Simulator,name=<iPhone>' test` (the same, and the UI launch tests). A work the tests cannot mock (it sends through a `let`, or reaches the network itself) is left out with a note saying what would open it; a call it cannot honour is refused with every reason and nothing is written. Not for an app's Ops tests (granite writes them) or a client package's own tests (network writes them).
        """#

    public static func output(from events: [TestsFrame]) -> TestsResult? { events.compactMap(\.result).last }

    public init() {}

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<TestsFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // The folder is the input's, else the host's: a host calling over the wire may say it only there.
                    var input = input
                    if input.directory == nil { input.directory = context.host.directory }
                    let result = try await Self.write(input, model: context.host.model, note: context.host.note) { continuation.yield($0) }
                    continuation.yield(.written(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole call: the app read, the tests made (the host's model asked where the code does not say), the app's
    /// run mode and schemes edited, everything staged, parsed and written together.
    static func write(_ input: Input, model: (any AgentHostModel)?, note: @escaping @Sendable (String) -> Void,
                      yield: @escaping @Sendable (TestsFrame) -> Void) async throws -> TestsResult {
        let files = AgentFiles(directory: input.directory)
        guard let project = AppProject.find(in: files.root) else {
            throw TestsError.refused(["\(files.root.path) holds no Xcode project: tests writes an app's tests once granite has made the app (`make: project`)"])
        }
        guard let unitTests = project.unitTests else {
            throw TestsError.refused(["\(project.project.lastPathComponent) has no unit-test target with a synchronized folder: tests writes into the one granite's project makes (`Tests`)"])
        }
        let index = AppIndex(project: project)
        var problems: [String] = [], notes: [String] = []

        // What to test: what the call names, else everything.
        var services: [ServiceInfo] = []
        // Left out: everything. An empty list: none.
        let namedServices = (input.services ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if input.services == nil {
            services = index.services.filter { !$0.works.isEmpty }
        } else {
            for name in namedServices {
                guard let service = index.service(named: name) ?? index.service(named: name + "Service") else {
                    problems.append("the app has no service `\(name)`: it has \(Self.list(index.services.map(\.name)))")
                    continue
                }
                if service.works.isEmpty { problems.append("\(service.name) has no work to test: its writer's changes are its Ops tests', which granite writes") }
                else if !services.contains(where: { $0.name == service.name }) { services.append(service) }
            }
        }
        var pages: [PageInfo] = []
        let namedPages = (input.pages ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if input.pages == nil {
            pages = index.pages
        } else {
            for name in namedPages {
                guard let page = index.pages.first(where: { $0.name == name }) else {
                    problems.append("the app has no page `\(name)`: it has \(Self.list(index.pages.map(\.name)))")
                    continue
                }
                if !pages.contains(where: { $0.name == page.name }) { pages.append(page) }
            }
        }
        let wantsUI = input.ui ?? true
        if wantsUI, project.uiTests == nil {
            if input.ui == true { problems.append("\(project.project.lastPathComponent) has no UI-test target with a synchronized folder (`UITests`): leave `ui` out or false") }
            else { notes.append("the project has no UI-test target, so no launch tests were written") }
        }
        let writesUI = wantsUI && project.uiTests != nil
        if services.isEmpty, pages.isEmpty, !writesUI {
            problems.append("there is nothing to test yet: the app has no services with work, no pages and no UI-test target; make them with granite first")
        }
        if let rounds = input.rounds, rounds < 1 { problems.append("`rounds` is \(rounds): give 1 or more, or leave it out") }
        guard problems.isEmpty else { throw TestsError.refused(problems) }
        let scenarios = Set(input.scenarios ?? TestsScenario.allCases).union([.normal])
        yield(.read(services: services.count, pages: pages.count, destinations: index.destinations?.cases.count ?? 0))
        note("reading \(project.name): \(services.count) service\(services.count == 1 ? "" : "s") with work, \(pages.count) page\(pages.count == 1 ? "" : "s"), \(index.destinations?.cases.count ?? 0) destinations")

        // The backends: a client the work sends through, answered by `mocks`'s `.mock()` or by a server of the tests.
        let backends = index.mockedClients.map { client in
            SupportEmitter.Backend(client: client, seams: index.seams.filter { $0.client == client.client && $0.isAssignable },
                                   usesMock: client.mock.map { mock in ["normal", "empty", "failing"].allSatisfy(mock.scenarios.contains) } ?? false)
        }
        // What the call writes fresh (refused over a file it did not write) and what it edits in place.
        var planned: [(url: URL, text: String)] = []
        var generated: [URL] = []
        func generate(_ url: URL, _ text: String) {
            planned.append((url, text))
            generated.append(url)
        }
        var count = 0
        var tested: [String] = [], drawn: [String] = [], destinations: [String] = []
        for service in services {
            let output = ServiceTestsEmitter(service: service, index: index, scenarios: scenarios, backends: backends).emit()
            notes += output.notes
            if let text = output.text {
                generate(unitTests.appendingPathComponent("\(service.name)Tests.swift"), text)
                count += output.tests
                tested.append(service.name)
            }
        }
        let asker = model.map { ExpectAsk(model: $0, rounds: min(max(input.rounds ?? 3, 1), 5), note: note) }
        for page in pages {
            let emitter = PageTestsEmitter(page: page, index: index, scenarios: scenarios, backends: backends)
            var asked: [String: [String]] = [:]
            if let asker {
                for plan in emitter.plans() where plan.skip == nil && !plan.undetermined.isEmpty {
                    note("asking what \(page.name).\(plan.action.name) leaves")
                    if let (expectations, rounds) = await asker.ask(page: page, plan: plan, index: index) {
                        asked[plan.action.name] = expectations
                        yield(.asked(page: page.name, action: plan.action.name, rounds: rounds))
                    } else {
                        asked[plan.action.name] = []
                        notes.append("\(page.name).\(plan.action.name): what it leaves did not come right in \(asker.rounds) round\(asker.rounds == 1 ? "" : "s"), so its test checks only that it ends without a failure")
                    }
                }
            }
            let output = emitter.emit(asked: asked, modelAsked: asker != nil)
            notes += output.notes
            if let text = output.text {
                generate(unitTests.appendingPathComponent("\(page.name)PageTests.swift"), text)
                count += output.tests
                drawn.append(page.name)
            }
        }
        if writesUI, let folder = project.uiTests {
            let output = LaunchTestsEmitter(index: index).emit()
            generate(folder.appendingPathComponent("\(LaunchTestsEmitter.type(project.name)).swift"), output.text)
            count += output.tests
            destinations = output.destinations
            notes += output.notes
            let iOS = project.uiTestTargets.filter { !$0.lowercased().contains("macos") }
            let mac = project.uiTestTargets.filter { $0.lowercased().contains("macos") }
            for scheme in project.schemes {
                let isMac = scheme.lastPathComponent.lowercased().contains("macos")
                guard let text = try? String(contentsOf: scheme, encoding: .utf8),
                      let edited = AppEdits.runningUITests(text, targets: isMac ? mac : iOS, run: !isMac) else { continue }
                planned.append((scheme, edited))
                notes.append(isMac
                             ? "\(scheme.deletingPathExtension().lastPathComponent) keeps the UI tests skipped: they need an interactive session on the Mac"
                             : "\(scheme.deletingPathExtension().lastPathComponent) runs the UI tests on the iOS simulator; the macOS scheme keeps them skipped, since they need an interactive session there")
            }
            // A launch on mocks needs the app to read `-mock`: `mocks`'s MockMode, or a client the turn wired to it.
            let readsMock = (index.files + index.packageFiles).contains { file in
                file.url.lastPathComponent != "RunMode.swift"
                    && (file.text.contains("forKey: \"mock\"") || file.text.contains("MockMode.isOn") || file.text.contains("[\"MOCK\"]"))
            }
            if !readsMock, !index.clients.isEmpty {
                notes.append("the app never reads `-mock`, so its launch tests run its pages against the live client: wire the client the services send through to its mock on `-mock YES` (the mocks agent's `MockMode`, or `.preview`)")
            }
            // Every UI test the app has launches it on mocks, so none reaches a live server.
            for file in SourceFiles.swift(under: folder, skipping: []) where !generated.contains(file.url) {
                guard let edited = AppEdits.launchingOnMocks(file.text) else { continue }
                planned.append((file.url, edited))
                notes.append("\(files.relative(file.url)) launches the app on mock backend responses too")
            }
        }

        // The support every test file leans on.
        let support = SupportEmitter(index: index, backends: backends)
        let folder = unitTests.appendingPathComponent("Support")
        if !tested.isEmpty || !drawn.isEmpty {
            generate(folder.appendingPathComponent("TestRoot.swift"), support.testRoot())
            generate(folder.appendingPathComponent("ServicesOnMocks.swift"), support.parentSuite())
            generate(folder.appendingPathComponent("BackendScenario.swift"), support.scenarios())
            if !drawn.isEmpty { generate(folder.appendingPathComponent("PageRender.swift"), support.pageRender()) }
            for backend in backends where !backend.usesMock {
                let server = ServerEmitter(client: backend.client, previews: index.previews, enums: index.enums)
                generate(folder.appendingPathComponent("\(server.type).swift"), server.file())
            }
            for backend in backends where backend.usesMock {
                notes.append("\(backend.client.client)'s tests answer through mocks' `.mock()`")
            }
        }

        // The app's run mode: no pages while it hosts its tests, and stores keyed apart.
        let runMode = AppEdits.runModeFile(index: index)
        if (try? String(contentsOf: runMode, encoding: .utf8)) != AppEdits.runMode { generate(runMode, AppEdits.runMode) }
        if let app = AppEdits.appFile(index) {
            if let edited = AppEdits.guardedApp(app.text) {
                planned.append((app.url, edited))
                notes.append("\(app.url.lastPathComponent) shows no page while the app hosts its unit tests, so nothing but the tests drives its services")
            } else if !app.text.contains("RunMode.showsPages") {
                notes.append("\(app.url.lastPathComponent) has no WindowGroup this can read: the app's pages run beside its unit tests and may race them")
            }
        }
        for service in index.services {
            guard let center = service.centerFile, let text = planned.first(where: { $0.url == center })?.text ?? (try? String(contentsOf: center, encoding: .utf8)),
                  let edited = AppEdits.keyedStore(text) else { continue }
            planned.append((center, edited))
            notes.append("\(service.name)'s store is kept apart under tests and mock launches (`\(service.persistKey ?? "")` + RunMode.storeSuffix)")
        }
        // A test file that names a package's types without importing the package does not build.
        let packageTypes = Self.packageTypes(index)
        let written = Set(planned.map(\.url.path))
        for file in SourceFiles.swift(under: unitTests, skipping: []) where !written.contains(file.url.path) {
            guard let edited = AppEdits.importingPackages(file.text, types: packageTypes) else { continue }
            planned.append((file.url, edited))
            notes.append("\(files.relative(file.url)) names a package's types without importing it: the import is added")
        }

        // A file this agent writes in place of one it did not write is refused, never overwritten.
        for url in generated {
            if let text = try? String(contentsOf: url, encoding: .utf8), !Self.isOurs(text) {
                problems.append("\(files.relative(url)) is not this agent's: move it, or rename what it tests")
            }
        }
        guard problems.isEmpty else { throw TestsError.refused(problems) }

        note("writing \(planned.count) files: \(count) tests")
        let paths = try files.write(planned)
        return TestsResult(path: paths.first, paths: paths, services: tested, pages: drawn, destinations: destinations, tests: count, notes: notes)
    }

    /// Whether `text` is a file this agent wrote.
    static func isOurs(_ text: String) -> Bool {
        let markers = ["extension ServicesOnMocks", "struct ServicesOnMocks", "final class TestRoot", "enum BackendScenario", "enum PageRender",
                       ": HTTPTransport, @unchecked Sendable", "DestinationTests: XCTestCase", "enum RunMode"]
        return markers.contains { text.contains($0) }
    }

    /// The types the app's packages declare, by name, with their module.
    static func packageTypes(_ index: AppIndex) -> [String: String] {
        var types: [String: String] = [:]
        for file in index.packageFiles {
            let parts = file.url.pathComponents
            guard let sources = parts.lastIndex(of: "Sources"), sources + 1 < parts.count else { continue }
            let module = parts[sources + 1]
            for name in SwiftText.matches(#"^public\s+(?:final\s+)?(?:struct|enum|class|actor|protocol)\s+(\w+)"#, in: file.text) { types[name] = module }
        }
        return types
    }

    static func list(_ names: [String]) -> String { names.isEmpty ? "none" : names.joined(separator: ", ") }
}
