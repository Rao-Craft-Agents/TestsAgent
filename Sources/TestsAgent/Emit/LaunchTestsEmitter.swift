//  WHAT: The app's UI tests: one launch a destination, on mock backend responses (`-mock YES`) and opened where the
//        launch asks (`-destination <case>`), asserting the destination's page comes on screen by its title.
//  PIN:  RUN ON THE iOS SIMULATOR. A Mac's UI tests need an interactive session to drive the app, so the macOS
//        scheme keeps them skipped; the iOS scheme runs them, headless.

import Foundation

struct LaunchTestsEmitter {
    let index: AppIndex

    struct Output {
        var text: String
        var destinations: [String]
        var tests: Int
        var notes: [String]
    }

    /// What a destination's page is titled on screen: its page's own title, else the destination's.
    func title(_ destination: DestinationInfo) -> String {
        if let page = destination.page.flatMap({ name in index.pages.first { $0.name == name } }), let title = page.title { return title }
        return destination.title ?? Naming.words(Naming.upperFirst(destination.name))
    }

    func emit() -> Output {
        let app = index.project.name
        var code = Code()
        var notes: [String] = []
        code.lines(["import XCTest", ""])
        let opens = index.destinations?.opensFromLaunch == true && !(index.destinations?.cases.isEmpty ?? true)
        if opens {
            code.line("/// Each of the app's destinations, opened at launch on mock backend responses: the app starts on it and shows its")
            code.line("/// page.")
        } else {
            code.line("/// The app launched on mock backend responses: it starts, and stays up.")
        }
        code.open("final class \(Self.type(app)): XCTestCase {")
        code.open("override func setUpWithError() throws {")
        code.line("continueAfterFailure = false")
        code.close()
        var destinations: [String] = []
        if opens, let cases = index.destinations?.cases {
            for destination in cases {
                let title = Naming.escaped(title(destination))
                code.line()
                code.line("@MainActor")
                code.open("func test\(Naming.upperFirst(destination.name))OpensAtLaunch() throws {")
                code.line("let app = launch(at: \"\(destination.name)\")")
                code.line("XCTAssertTrue(shows(\"\(title)\", in: app), \"the app opens on \(title)\")")
                code.close()
                destinations.append(destination.name)
            }
        } else {
            notes.append(index.destinations == nil
                         ? "the app has no destinations yet (`make: navigation`), so its UI test checks only that it launches on mocks"
                         : "the app does not open the destination a launch names (`-destination`), so its UI test checks only that it launches on mocks")
            code.line()
            code.line("@MainActor")
            code.open("func testLaunchesOnMocks() throws {")
            code.line("let app = XCUIApplication()")
            code.line("app.launchArguments += [\"-mock\", \"YES\"]")
            code.line("app.launch()")
            code.line("XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))")
            code.close()
        }
        if opens {
            code.line()
            code.line("/// The app launched on mock backend responses, opening at `destination`.")
            code.line("@MainActor")
            code.open("private func launch(at destination: String) -> XCUIApplication {")
            code.lines(["let app = XCUIApplication()", "app.launchArguments += [\"-mock\", \"YES\", \"-destination\", destination]",
                        "app.launch()", "return app"])
            code.close()
            code.line()
            code.line("/// Whether the page titled `title` comes on screen: its navigation bar on iPhone and iPad, its window's title on")
            code.line("/// the Mac.")
            code.line("@MainActor")
            code.open("private func shows(_ title: String, in app: XCUIApplication) -> Bool {")
            code.line("#if os(iOS)")
            code.line("return app.navigationBars[title].waitForExistence(timeout: 20)")
            code.line("#else")
            code.line("return app.windows[title].waitForExistence(timeout: 20) || app.staticTexts[title].waitForExistence(timeout: 1)")
            code.line("#endif")
            code.close()
        }
        code.close()
        return Output(text: code.text, destinations: destinations, tests: max(destinations.count, 1), notes: notes)
    }

    static func type(_ app: String) -> String { AppProject.identifier(app) + "DestinationTests" }
}
