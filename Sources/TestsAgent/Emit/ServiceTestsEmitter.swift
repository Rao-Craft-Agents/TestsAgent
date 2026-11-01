//  WHAT: A service's tests: for each piece of its work, its ticketed entry called with the backend mocked, and the
//        state the work should leave asserted: the field it fills or adds to, `loading` cleared, `lastError` set when
//        the backend fails and cleared by a try again, nothing added past the last page, the work marked while in
//        flight, and what its Ops do with any other kind it sets.
//  PIN:  ASSERTED AGAINST WHAT THE ENTRY ANSWERED. The value the work wrote is the value its ticket resolved with,
//        so a test holds whatever backend answers it (`mocks`'s fixtures or the tests' own server).
//  PIN:  A WORK A TEST CANNOT MOCK IS NOT TESTED. A call through something a test cannot assign, or one that reaches
//        the network itself, would reach a live server: it is left out, and a note says what would open it.

import Foundation

struct ServiceTestsEmitter {
    let service: ServiceInfo
    let index: AppIndex
    let scenarios: Set<TestsScenario>
    let backends: [SupportEmitter.Backend]

    struct Output {
        var text: String?
        var tests = 0
        var notes: [String] = []
    }

    private var root: String { "root.\(Naming.member(service.relay))" }

    func emit() -> Output {
        var output = Output()
        var code = Code()
        let imports = ["Foundation", "Testing"] + service.imports
        code.lines(imports.map { "import \($0)" } + ["@testable import \(index.project.module)", ""])
        code.open("extension ServicesOnMocks {")
        let mocked = service.works.contains { index.reach(service, $0).isMocked }
        code.doc("\(service.name)'s work\(mocked ? " on mock backend responses" : ""): what each piece of work leaves in its state.")
        code.open("@Suite @MainActor struct \(service.name)Tests {")
        code.line("let root = TestRoot.shared")
        for work in service.works {
            let (tests, note) = self.tests(for: work)
            if let note { output.notes.append(note) }
            guard !tests.isEmpty else { continue }
            code.line()
            code.line("// MARK: - \(work.verb)")
            for test in tests {
                code.line()
                code.lines(test)
                output.tests += 1
            }
        }
        code.close()
        code.close()
        if output.tests > 0 { output.text = code.text }
        return output
    }

    /// The tests of one piece of work, each a test function's lines; or why there are none.
    func tests(for work: WorkInfo) -> ([[String]], String?) {
        let reach = index.reach(service, work)
        let name = "\(service.name).\(work.verb)"
        if let live = reach.live { return ([], "\(name) is not tested: \(live), which a test cannot stand in front of") }
        if let receiver = reach.unread.first {
            return ([], "\(name) is not tested: it calls an endpoint through `\(receiver)`, which a test cannot put a mock behind; send through a static the tests can assign, like `\(reach.calls.first?.seam.client ?? "Client").current`")
        }
        if let locked = reach.calls.first(where: { !$0.seam.isAssignable }) {
            return ([], "\(name) is not tested: `\(locked.seam.path)` cannot be assigned, so a test cannot put a mock behind it; declare it `static var \(locked.seam.path.split(separator: ".").last ?? "current"): \(locked.seam.client) = …`")
        }
        if let unanswered = reach.calls.first(where: { call in
            guard let client = index.client(call.seam.client), let endpoint = client.endpoint(call.endpoint) else { return false }
            if backends.first(where: { $0.client.client == client.client })?.usesMock == true { return false }
            if case .unanswerable = ServerEmitter(client: client, previews: index.previews, enums: index.enums).answer(endpoint) { return true }
            return false
        }) {
            return ([], "\(name) is not tested: \(unanswered.endpoint)'s answer has no preview for the tests' server to answer with")
        }
        guard let first = Arguments.make(work.entry.parameters, page: 1, index: index),
              let second = Arguments.make(work.entry.parameters, page: 2, index: index) else {
            return ([], "\(name) is not tested: a parameter of `\(work.entry.name)` has no sample value a test can pass")
        }
        let mocked = reach.isMocked
        // An append after a page loaded asks for the next page; anything else asks for the first.
        let seedsAppend = work.write.field.map { fieldName in
            service.works.contains { $0.write == .replace(fieldName) && $0.entry.returns != nil && Arguments.make($0.entry.parameters, page: 1, index: index) != nil }
        } ?? false
        let inFlight: Arguments = {
            if case .append = work.write, seedsAppend, second.hasPage { return second }
            return first
        }()
        let field = work.write.field.flatMap(service.field)
        let isList = Samples.element(of: field?.type) != nil
        let returns = work.entry.returns != nil
        var tests: [[String]] = []
        switch work.write {
        case .replace(let fieldName):
            let f = Naming.member(fieldName)
            if returns {
                var lines = [head(isList ? "\(work.verb)Fills\(Naming.upperFirst(fieldName))" : "\(work.verb)Sets\(Naming.upperFirst(fieldName))"),
                             "    await root.boot(.normal)",
                             "    let value = try await \(call(work, first))",
                             "    await root.settle()"]
                if isList && mocked { lines.append("    #expect(!value.isEmpty)") }
                lines.append("    #expect(\(root).state.\(f) == value)")
                lines += status().map { "    " + $0 } + opsExpectations(work, first).map { "    " + $0 } + ["}"]
                tests.append(lines)
                if mocked, first.hasPage {
                    tests.append([head("\(work.verb)AgainReplaces\(Naming.upperFirst(fieldName))"),
                                  "    await root.boot(.normal)",
                                  "    try await \(call(work, first))",
                                  "    let value = try await \(call(work, second))",
                                  "    await root.settle()",
                                  "    #expect(\(root).state.\(f) == value)", "}"])
                }
            }
            if mocked, isList, scenarios.contains(.empty) {
                tests.append([head("\(work.verb)WithNothingToShowLeaves\(Naming.upperFirst(fieldName))Empty"),
                              "    await root.boot(.empty)",
                              "    try await \(call(work, first))",
                              "    await root.settle()",
                              Samples.isOptional(field?.type) ? "    #expect(\(root).state.\(f)?.isEmpty ?? true)" : "    #expect(\(root).state.\(f).isEmpty)"]
                             + status().map { "    " + $0 } + ["}"])
            }
            if mocked, scenarios.contains(.failing) {
                var lines = [head("aFailed\(Naming.upperFirst(work.verb))SaysWhyAndATryAgainClearsIt"),
                             "    await root.boot(.failing)",
                             "    await #expect(throws: (any Error).self) { try await \(call(work, first)) }",
                             "    await root.settle()"]
                lines += failureStatus().map { "    " + $0 }
                lines.append("    #expect(\(root).state.\(f) == \(service.name).Center.State().\(f))")
                lines += ["", "    root.answer(.normal)"]
                if returns {
                    lines += ["    let value = try await \(call(work, first))", "    await root.settle()",
                              "    #expect(\(root).state.lastError == nil)".onlyIf(service.hasStatus),
                              "    #expect(\(root).state.\(f) == value)"].compactMap { $0 }
                } else {
                    lines += ["    try await \(call(work, first))", "    await root.settle()",
                              "    #expect(\(root).state.lastError == nil)".onlyIf(service.hasStatus)].compactMap { $0 }
                }
                tests.append(lines + ["}"])
            }
        case .append(let fieldName):
            let f = Naming.member(fieldName)
            let optional = Samples.isOptional(field?.type)
            let seed = service.works.first { other in
                other.write == .replace(fieldName) && other.entry.returns != nil
                    && (Arguments.make(other.entry.parameters, page: 1, index: index) != nil)
            }
            let seedArguments = seed.flatMap { Arguments.make($0.entry.parameters, page: 1, index: index) }
            let appendArguments = inFlight
            let firstLine = seed.map { "    let first = try await \(call($0, seedArguments!))" } ?? "    let first = \(root).state.\(f)"
            let joined = optional ? "(first ?? []) + next" : "first + next"
            if returns {
                var lines = [head("\(work.verb)AddsTheNextPageTo\(Naming.upperFirst(fieldName))"), "    await root.boot(.normal)", firstLine,
                             "    let next = try await \(call(work, appendArguments))", "    await root.settle()"]
                if mocked { lines.append("    #expect(!next.isEmpty)") }
                lines.append("    #expect(\(root).state.\(f) == \(joined))")
                tests.append(lines + status().map { "    " + $0 } + ["}"])
            }
            if mocked, scenarios.contains(.empty) {
                tests.append([head("\(work.verb)WithNothingLeftKeeps\(Naming.upperFirst(fieldName))"), "    await root.boot(.normal)", firstLine,
                              "    root.answer(.empty)", "    try await \(call(work, appendArguments))", "    await root.settle()",
                              "    #expect(\(root).state.\(f) == first)",
                              "    #expect(\(root).state.lastError == nil)".onlyIf(service.hasStatus), "}"].compactMap { $0 })
            }
            if mocked, scenarios.contains(.failing) {
                var lines = [head("aFailed\(Naming.upperFirst(work.verb))Keeps\(Naming.upperFirst(fieldName))AndATryAgainAddsThePage"),
                             "    await root.boot(.normal)", firstLine, "    root.answer(.failing)",
                             "    await #expect(throws: (any Error).self) { try await \(call(work, appendArguments)) }", "    await root.settle()"]
                lines += failureStatus().map { "    " + $0 }
                lines.append("    #expect(\(root).state.\(f) == first)")
                lines += ["", "    root.answer(.normal)"]
                if returns {
                    lines += ["    let next = try await \(call(work, appendArguments))", "    await root.settle()",
                              "    #expect(\(root).state.lastError == nil)".onlyIf(service.hasStatus),
                              "    #expect(\(root).state.\(f) == \(joined))"].compactMap { $0 }
                } else {
                    lines += ["    try await \(call(work, appendArguments))", "    await root.settle()",
                              "    #expect(\(root).state.lastError == nil)".onlyIf(service.hasStatus)].compactMap { $0 }
                }
                tests.append(lines + ["}"])
            }
        case .none:
            var lines = [head(mocked ? "\(work.verb)ReachesTheBackend" : "\(work.verb)LeavesItsState"), "    await root.boot(.normal)",
                         "    try await \(call(work, first))", "    await root.settle()"]
            for endpointCall in reach.calls {
                guard let backend = backends.first(where: { $0.client.client == endpointCall.seam.client }), !backend.usesMock,
                      let endpoint = backend.client.endpoint(endpointCall.endpoint) else { continue }
                let check = "    #expect(root.\(backend.property).received(\"\(endpoint.method)\", \"\(Naming.escaped(endpoint.path))\"))"
                if !lines.contains(check) { lines.append(check) }
            }
            lines += opsExpectations(work, first).map { "    " + $0 } + status().map { "    " + $0 }
            tests.append(lines + ["}"])
            if mocked, scenarios.contains(.failing) {
                var lines = [head("aFailed\(Naming.upperFirst(work.verb))SaysWhyAndATryAgainClearsIt"), "    await root.boot(.failing)",
                             "    await #expect(throws: (any Error).self) { try await \(call(work, first)) }", "    await root.settle()"]
                lines += failureStatus().map { "    " + $0 }
                lines += ["", "    root.answer(.normal)", "    try await \(call(work, first))", "    await root.settle()",
                          "    #expect(\(root).state.lastError == nil)".onlyIf(service.hasStatus)].compactMap { $0 }
                tests.append(lines + ["}"])
            }
        }
        if mocked, scenarios.contains(.slow), let key = work.loadingKey, service.hasStatus {
            tests.append([head("\(work.verb)IsMarkedWhileInFlight"), "    await root.boot(.slow)",
                          "    let service = \(root)",
                          "    let work = Task { try await service.\(Naming.member(work.entry.name))(\(inFlight.text)) }",
                          "    #expect(await root.until { service.state.loading == \"\(Naming.escaped(key))\" })",
                          "    _ = try await work.value", "    await root.settle()",
                          "    #expect(\(root).state.loading == nil)", "}"])
        }
        return (tests, nil)
    }

    private func head(_ name: String) -> String { "@Test func \(name)() async throws {" }

    private func call(_ work: WorkInfo, _ arguments: Arguments) -> String {
        "\(root).\(Naming.member(work.entry.name))(\(arguments.text))"
    }

    /// `loading` cleared and nothing failed, when the service says either.
    private func status() -> [String] {
        service.hasStatus ? ["#expect(\(root).state.loading == nil)", "#expect(\(root).state.lastError == nil)"] : []
    }

    /// Why the work failed recorded, and nothing left in flight.
    private func failureStatus() -> [String] {
        service.hasStatus ? ["#expect(\(root).state.lastError != nil)", "#expect(\(root).state.loading == nil)"] : []
    }

    /// What the Ops do with the kinds `work` sets beside its result: each plain assignment whose value the test
    /// knows (a literal, or an argument it passed).
    func opsExpectations(_ work: WorkInfo, _ arguments: Arguments) -> [String] {
        var lines: [String] = []
        for call in work.sets {
            for line in OpsExpectations.lines(call, service: service, root: root, value: { argument in
                let name = argument.hasPrefix("meta.") ? String(argument.dropFirst(5)) : (work.payloadNames[argument] ?? argument)
                return arguments.values[name]
            }) where !lines.contains(line) {
                lines.append(line)
            }
        }
        return lines
    }
}
