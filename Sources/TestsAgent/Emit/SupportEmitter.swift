//  WHAT: The tests' support: the one serialized suite every service and page suite nests in, the scenarios a mock
//        backend answers, the offscreen renderer pages are drawn with, and the root that holds the app's services
//        for the tests and boots them on mocks.
//  PIN:  ONE PARENT, SERIALIZED. A relay is the process's one instance of its service, and Swift Testing runs
//        separate suites side by side even when each is serialized; nested under one `.serialized` parent, every
//        suite that touches a service runs one test at a time (the granite skill's testing rule).
//  PIN:  QUIET BEFORE EACH TEST. A page drawn offscreen may start its own work (`ImageRenderer` runs `.task` on
//        iOS); the root waits until no service has work in flight before it clears them for the next test.

import Foundation

struct SupportEmitter {
    let index: AppIndex
    /// The clients the tests put mocks behind, and whether each answers through `mocks`'s `.mock()`.
    let backends: [Backend]

    struct Backend {
        let client: ClientInfo
        /// The seams that hold it.
        let seams: [Seam]
        /// Whether `mocks`'s `.mock(_:latency:)` answers for it; else a server of the tests' own.
        let usesMock: Bool
        var server: String { ServerEmitter.type(of: client) }
        var property: String { Naming.lowerFirst(server) }
    }

    var module: String { index.project.module }

    func parentSuite() -> String {
        """
        import Testing

        /// Every suite that drives the app's services runs nested in this one, one test at a time: the services are the
        /// process's own (a relay is a singleton), and Swift Testing runs separate suites side by side even when each one
        /// is serialized.
        @Suite(.serialized) @MainActor struct ServicesOnMocks {}

        """
    }

    func scenarios() -> String {
        """
        /// What the mock backend answers during a test.
        enum BackendScenario: String, CaseIterable, Sendable {
            /// Pages of items, then an empty page; every other endpoint its sample.
            case normal
            /// Every list empty.
            case empty
            /// Every request a server error.
            case failing
            /// As normal, a moment late, so work is seen in flight.
            case slow
        }

        """
    }

    func pageRender() -> String {
        """
        import SwiftUI

        /// A page drawn offscreen at an iPhone's size: what a page test draws to prove the page builds in a state without
        /// trapping. The page is drawn bare, as `ImageRenderer` can draw it: a navigation stack is UIKit's on iOS and is
        /// never flattened into an image.
        enum PageRender {
            /// `page` drawn in `scheme`; nil when nothing was drawn.
            @MainActor
            static func draw(_ page: some View, scheme: ColorScheme) -> CGImage? {
                let renderer = ImageRenderer(content: page
                    .environment(\\.colorScheme, scheme)
                    .frame(width: 390, height: 844))
                return renderer.cgImage
            }
        }

        """
    }

    func testRoot() -> String {
        var code = Code()
        var imports = ["Foundation", "Granite"]
        for backend in backends where !imports.contains(backend.client.module) { imports.append(backend.client.module) }
        code.lines(imports.map { "import \($0)" } + ["@testable import \(module)", ""])
        code.line("/// The app's services as its tests hold them: a relay to each for the whole run (a relay is the process's one")
        code.line("/// instance of its service), and every client the services send through answering from a mock backend.")
        code.line("@MainActor")
        code.open("final class TestRoot {")
        code.line("static let shared = TestRoot()")
        code.line()
        for service in index.services { code.line("@Relay(.silence) var \(Naming.member(service.relay)): \(service.name)") }
        let served = backends.filter { !$0.usesMock }
        if !served.isEmpty {
            code.line()
            for backend in served {
                code.line("/// \(backend.client.module)'s server for the current test.")
                code.line("private(set) var \(backend.property) = \(backend.server)(.normal)")
            }
        }
        code.line()
        code.line("private init() {}")
        code.line()
        code.line("/// Every service back at its start, its stored state read, and the backend answering `scenario`: what each")
        code.line("/// test calls first.")
        code.open("func boot(_ scenario: BackendScenario = .normal) async {")
        code.line("await quiet()")
        code.line(backends.isEmpty ? "_ = scenario" : "answer(scenario)")
        let persisted = index.services.filter(\.isPersisted)
        if !persisted.isEmpty {
            code.line("await until(seconds: 5) { \(persisted.map { "self.\(Naming.member($0.relay)).isLoaded" }.joined(separator: " && ")) }")
        }
        for service in index.services where service.hasClear { code.line("\(Naming.member(service.relay)).set(.clear)") }
        code.line("await settle()")
        code.close()
        if !backends.isEmpty {
            code.line()
            code.line("/// The backend answers `scenario` from now on: a try again after a failure, the last page.")
            code.open("func answer(_ scenario: BackendScenario) {")
            for backend in backends {
                if backend.usesMock {
                    let mock = backend.client.mock!
                    code.line("switch scenario {")
                    for scenario in TestsScenario.allCases {
                        let latency = scenario == .slow ? ".milliseconds(400)" : ".zero"
                        let name = mock.scenarios.contains(scenario.rawValue) ? scenario.rawValue : "normal"
                        let made = mock.takesLatency ? ".mock(.\(name), latency: \(latency))" : ".mock(.\(name))"
                        code.line("case .\(scenario.rawValue):")
                        for seam in backend.seams { code.line("    \(seam.path) = \(made)") }
                    }
                    code.line("}")
                } else {
                    code.line("\(backend.property) = \(backend.server)(scenario)")
                    for seam in backend.seams { code.line("\(seam.path) = \(backend.property).client") }
                }
            }
            code.close()
        }
        let status = index.services.filter(\.hasStatus)
        code.line()
        code.line("/// Whether no service has work in flight.")
        code.open("var isIdle: Bool {")
        if status.isEmpty { code.line("true") }
        let checks = status.map { "\(Naming.member($0.relay)).state.loading == nil" }
        var line = ""
        for (position, check) in checks.enumerated() {
            let piece = position == 0 ? check : " && " + check
            if line.count + piece.count > 100, !line.isEmpty {
                code.line(line)
                line = "    &&" + piece.dropFirst(3)
            } else {
                line += piece
            }
        }
        if !line.isEmpty { code.line(line) }
        code.close()
        code.line()
        code.lines([
            "/// Waits until no service has had work in flight for a few turns, up to five seconds: work a page started on its",
            "/// own when it was drawn ends before the next test begins.",
        ])
        code.open("func quiet() async {")
        code.lines(["var calm = 0", "let deadline = Date().addingTimeInterval(5)"])
        code.open("while calm < 8, Date() < deadline {")
        code.lines(["await settle()", "calm = isIdle ? calm + 1 : 0", "try? await Task.sleep(for: .milliseconds(10))"])
        code.close()
        code.close()
        code.line()
        code.line("/// Lets the main queue run what was sent to it: a service's writer commits a turn after its send.")
        code.open("func settle() async {")
        code.open("for _ in 0..<2 {")
        code.line("await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { done.resume() } }")
        code.close()
        code.close()
        code.line()
        code.line("/// Waits until `condition` holds, up to `seconds`; whether it came to hold.")
        code.line("@discardableResult")
        code.open("func until(seconds: Double = 2, _ condition: () -> Bool) async -> Bool {")
        code.line("let deadline = Date().addingTimeInterval(seconds)")
        code.open("while !condition() {")
        code.lines(["guard Date() < deadline else { return false }", "try? await Task.sleep(for: .milliseconds(10))"])
        code.close()
        code.line("return true")
        code.close()
        code.close()
        return code.text
    }
}
