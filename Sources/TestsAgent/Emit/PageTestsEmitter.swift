//  WHAT: A page's tests: the page built with its services on mocks and drawn offscreen in light and dark in each
//        state its services can be in (loaded, empty, failing), and each action of its `+Actions` run as a tap runs
//        it, with the state it leaves asserted.
//  PIN:  WHAT AN ACTION LEAVES IS READ OFF ITS STATEMENTS. A call of a service's entry leaves what that work writes
//        (filled, added to, reached the backend); a `set(.field(value))` leaves the field at the value. Only a
//        statement that says neither is asked of the host's model, and its answer is checked before it is written.

import Foundation

struct PageTestsEmitter {
    let page: PageInfo
    let index: AppIndex
    let scenarios: Set<TestsScenario>
    let backends: [SupportEmitter.Backend]

    struct Output {
        var text: String?
        var tests = 0
        var notes: [String] = []
    }

    /// One action, read: what the test passes it, what it is expected to leave, and what the code does not say.
    struct ActionPlan {
        var action: ActionInfo
        /// The test's name.
        var name: String
        /// Lines that bind each parameter before the call.
        var bindings: [String]
        /// Whether the page is refreshed before the action, so it has something to act on.
        var refreshesFirst: Bool
        /// Lines that read what the action is checked against before it runs.
        var before: [String]
        /// The expectations read off the code.
        var expectations: [String]
        /// The statements the code does not say the outcome of.
        var undetermined: [String]
        /// Why the action cannot be tested, when it cannot.
        var skip: String?
    }

    /// How the page is made: its inputs from samples; nil when one has none.
    var construction: String? {
        guard let arguments = Arguments.make(page.inputs, page: 1, index: index) else { return nil }
        return "\(page.name)(\(arguments.text))"
    }

    var refresh: ActionInfo? { page.action("refresh").flatMap { $0.parameters.isEmpty ? $0 : nil } }

    /// Whether the page's refresh reaches a mocked backend, so drawing it loaded, empty and failing differs.
    var refreshReachesBackend: Bool {
        guard let refresh else { return false }
        return refresh.statements.contains { statement in
            guard let (service, work) = entryCall(statement) else { return false }
            return index.reach(service, work).isMocked
        }
    }

    /// `try await recipes.load(page: 1)` as the service and the work it calls.
    func entryCall(_ statement: String) -> (ServiceInfo, WorkInfo)? {
        guard let match = SwiftText.groups(#"^(?:_\s*=\s*)?(?:try[?!]?\s+)?await\s+(\w+)\.(\w+)\("#, in: statement).first,
              let relay = page.relay(match[1]), let service = index.service(of: relay),
              let work = service.works.first(where: { $0.entry.name == match[2] }) else { return nil }
        return (service, work)
    }

    func plans() -> [ActionPlan] {
        page.actions.compactMap(plan)
    }

    func plan(_ action: ActionInfo) -> ActionPlan? {
        guard !action.statements.isEmpty else { return nil }
        var plan = ActionPlan(action: action, name: action.name, bindings: [], refreshesFirst: false, before: [], expectations: [],
                              undetermined: [], skip: nil)
        var outcome = "Runs"
        var touched: [ServiceInfo] = []
        // Each parameter: an item the page lists after a refresh, else a sample.
        for parameter in action.parameters {
            if let (relay, field) = listed(parameter.type), refresh != nil, action.name != "refresh" {
                plan.refreshesFirst = true
                plan.bindings.append("let \(Naming.member(parameter.name)) = try #require(root.\(Naming.member(relay)).state.\(Naming.member(field))\(Samples.isOptional(fieldType(relay, field)) ? "?" : "").first)")
            } else if let value = Samples.value(parameter.type, name: parameter.name, previews: index.previews, enums: index.enums) {
                plan.bindings.append("let \(Naming.member(parameter.name)) = \(value)")
            } else {
                plan.skip = "\(page.name).\(action.name) is not tested: its `\(parameter.name)` has no sample value a test can pass"
                return plan
            }
        }
        let names = Set(action.parameters.map(\.name))
        for statement in action.statements {
            if let (service, work) = entryCall(statement) {
                let reach = index.reach(service, work)
                if !reach.calls.isEmpty, !reach.isMocked || reach.live != nil {
                    plan.skip = "\(page.name).\(action.name) is not tested: it runs \(service.name).\(work.verb), which a test cannot put a mock behind"
                    return plan
                }
                let r = "root.\(Naming.member(service.relay))"
                switch work.write {
                case .replace(let field):
                    let type = service.field(field)?.type
                    if Samples.element(of: type) != nil, reach.isMocked {
                        plan.expectations.append(Samples.isOptional(type) ? "#expect(\(r).state.\(Naming.member(field))?.isEmpty == false)" : "#expect(!\(r).state.\(Naming.member(field)).isEmpty)")
                        if outcome == "Runs" { outcome = "Fills" + Naming.upperFirst(field) }
                    } else if Samples.isOptional(type), reach.isMocked {
                        plan.expectations.append("#expect(\(r).state.\(Naming.member(field)) != nil)")
                        if outcome == "Runs" { outcome = "Sets" + Naming.upperFirst(field) }
                    }
                case .append(let field):
                    let count = Samples.isOptional(service.field(field)?.type) ? "(\(r).state.\(Naming.member(field))?.count ?? 0)" : "\(r).state.\(Naming.member(field)).count"
                    if refresh != nil, action.name != "refresh" { plan.refreshesFirst = true }
                    let before = "before\(Naming.upperFirst(field))"
                    plan.before.append("let \(before) = \(count)")
                    if reach.isMocked { plan.expectations.append("#expect(\(count) > \(before))") }
                    if outcome == "Runs" { outcome = "AddsTo" + Naming.upperFirst(field) }
                case .none:
                    for call in reach.calls {
                        guard let backend = backends.first(where: { $0.client.client == call.seam.client }), !backend.usesMock,
                              let endpoint = backend.client.endpoint(call.endpoint) else { continue }
                        plan.expectations.append("#expect(root.\(backend.property).received(\"\(endpoint.method)\", \"\(Naming.escaped(endpoint.path))\"))")
                        if outcome == "Runs" { outcome = "ReachesTheBackend" }
                    }
                }
                if !touched.contains(where: { $0.name == service.name }) { touched.append(service) }
            } else if let (service, call) = setThrough(statement, names: names) {
                let said = OpsExpectations.lines(call, service: service, root: "root.\(Naming.member(service.relay))") { argument in
                    Self.isSayable(argument, names: names) ? argument : nil
                }
                if said.isEmpty {
                    plan.undetermined.append(statement)
                } else {
                    plan.expectations += said.filter { !plan.expectations.contains($0) }
                    if outcome == "Runs" { outcome = "Sets" + Naming.upperFirst(SwiftText.matches(#"state\.(\w+)"#, in: said[0]).first ?? call.kind) }
                }
            } else {
                plan.undetermined.append(statement)
            }
        }
        for service in touched where service.hasStatus {
            let r = "root.\(Naming.member(service.relay))"
            plan.expectations += ["#expect(\(r).state.loading == nil)", "#expect(\(r).state.lastError == nil)"]
        }
        // With nothing else to say, the action ends without a failure in any service the page reads.
        if plan.expectations.isEmpty {
            for relay in page.relays {
                guard let service = index.service(of: relay), service.hasStatus else { continue }
                let check = "#expect(root.\(Naming.member(service.relay)).state.lastError == nil)"
                if !plan.expectations.contains(check) { plan.expectations.append(check) }
            }
        }
        plan.name = action.name + outcome
        return plan
    }

    /// `layout.select(.settings)` or `layout.set(.destination(.settings))` as the set it makes, its arguments in the
    /// action's own terms: a helper's parameters replaced by what the action passes.
    func setThrough(_ statement: String, names: Set<String>) -> (ServiceInfo, SetCall)? {
        let text = statement.replacingOccurrences(of: #"^(?:try[?!]?\s+)?(?:await\s+)?"#, with: "", options: .regularExpression)
        guard let match = SwiftText.groups(#"^(\w+)\.(\w+)\((.*)\)$"#, in: text).first,
              let relay = page.relay(match[1]), let service = index.service(of: relay) else { return nil }
        if match[2] == "set" {
            guard let call = ServiceReader.setCalls(in: "self." + text.dropFirst(match[1].count + 1), owner: "self").first else { return nil }
            return (service, call)
        }
        guard let helper = service.helper(match[2]) else { return nil }
        let given = SwiftText.split(match[3], on: ",")
        guard given.count == helper.parameters.count else { return nil }
        var values: [String: String] = [:]
        for (parameter, argument) in zip(helper.parameters, given) {
            var value = argument
            if let label = parameter.label, value.hasPrefix(label + ":") { value = String(value.dropFirst(label.count + 1)) }
            values[parameter.name] = value.trimmingCharacters(in: .whitespaces)
        }
        let arguments = helper.set.arguments.map { values[$0] ?? $0 }
        return (service, SetCall(kind: helper.set.kind, arguments: arguments))
    }

    /// Whether the test can say `expression` as the action did: literals, the action's parameters and what they
    /// hold, types and plain calls of them; never a page's state or a relay, which the action may have changed.
    static func isSayable(_ expression: String, names: Set<String>) -> Bool {
        if Samples.isLiteral(expression) { return true }
        if expression.contains("state") || expression.contains("{") || expression.contains("=") { return false }
        var stripped = expression.replacingOccurrences(of: #""(?:[^"\\]|\\.)*""#, with: "", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"\.\w+"#, with: "", options: .regularExpression)
        let roots = SwiftText.matches(#"\b([a-z_]\w*)\b"#, in: stripped)
        return roots.allSatisfy { names.contains($0) || ["nil", "true", "false"].contains($0) }
    }

    /// A relay's service field that lists `type`: (the root's relay, the field).
    private func listed(_ type: String) -> (String, String)? {
        for relay in page.relays {
            guard let service = index.service(of: relay) else { continue }
            if let field = service.fields.first(where: { Samples.element(of: $0.type) == type }) { return (service.relay, field.name) }
        }
        return nil
    }

    private func fieldType(_ relay: String, _ field: String) -> String? {
        index.services.first { $0.relay == relay }?.field(field)?.type
    }

    /// The page's tests; `asked` holds what the host's model said each undetermined action leaves (empty when it never
    /// came right), and `modelAsked` whether there was a model to ask.
    func emit(asked: [String: [String]] = [:], modelAsked: Bool = false) -> Output {
        var output = Output()
        guard let made = construction else {
            output.notes.append("\(page.name) is not tested: an input it is made with has no sample value")
            return output
        }
        var code = Code()
        let imports = ["Foundation", "SwiftUI", "Testing"] + page.imports
        code.lines(imports.map { "import \($0)" } + ["@testable import \(index.project.module)", ""])
        code.open("extension ServicesOnMocks {")
        let drawn = refreshReachesBackend ? [TestsScenario.normal] + [.empty, .failing].filter(scenarios.contains) : [.normal]
        let acts = plans().contains { $0.skip == nil }
        code.doc("\(page.name) on mock backend responses: drawn in light and dark"
                 + (drawn.count > 1 ? " in each state its services can be in" : "")
                 + (acts ? ", and its actions run as a tap runs them, with the state they leave." : "."))
        code.open("@Suite @MainActor struct \(page.name)PageTests {")
        code.line("let root = TestRoot.shared")
        code.line()
        if drawn.count > 1 {
            code.line("@Test(arguments: [\(drawn.map { "BackendScenario.\($0.rawValue)" }.joined(separator: ", ").replacingOccurrences(of: ", BackendScenario.", with: ", ."))])")
            code.open("func drawsInLightAndDark(_ scenario: BackendScenario) async throws {")
            code.line("await root.boot(scenario)")
        } else {
            code.open("@Test func drawsInLightAndDark() async throws {")
            code.line("await root.boot(.normal)")
        }
        if let refresh { code.line(call(refresh, on: made, arguments: "", tryWord: "try?")) }
        code.line("await root.quiet()")
        code.line("#expect(PageRender.draw(\(made), scheme: .light) != nil)")
        code.line("#expect(PageRender.draw(\(made), scheme: .dark) != nil)")
        code.line("await root.quiet()")
        code.close()
        output.tests += 1
        var names: Set<String> = ["drawsInLightAndDark"]
        for var plan in plans() {
            if let skip = plan.skip {
                output.notes.append(skip)
                continue
            }
            if let said = asked[plan.action.name], !said.isEmpty {
                plan.expectations += said
            } else if !plan.undetermined.isEmpty, !modelAsked {
                output.notes.append("\(page.name).\(plan.action.name)'s test checks only that it ends without a failure: what `\(plan.undetermined[0])` leaves is not in the code, and there was no model to ask")
            }
            var name = plan.name
            while names.contains(name) { name += "Again" }
            names.insert(name)
            code.line()
            code.open("@Test func \(name)() async throws {")
            code.line("await root.boot(.normal)")
            code.line("let page = \(made)")
            if plan.refreshesFirst, let refresh {
                code.line(call(refresh, on: "page", arguments: "", tryWord: "try"))
                code.line("await root.settle()")
            }
            code.lines(plan.bindings + plan.before)
            let arguments = plan.action.parameters.map { ($0.label.map { "\($0): " } ?? "") + Naming.member($0.name) }.joined(separator: ", ")
            code.line(call(plan.action, on: "page", arguments: arguments, tryWord: "try"))
            code.line("await root.settle()")
            code.lines(plan.expectations)
            code.close()
            output.tests += 1
        }
        code.close()
        code.close()
        output.text = code.text
        return output
    }

    private func call(_ action: ActionInfo, on receiver: String, arguments: String, tryWord: String) -> String {
        let prefix = (action.isThrowing ? tryWord + " " : "") + (action.isAsync ? "await " : "")
        return "\(prefix)\(receiver).\(Naming.member(action.name))(\(arguments))"
    }
}
