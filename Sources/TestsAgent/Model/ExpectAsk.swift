//  WHAT: What a page action leaves behind, asked of the host's model when the code does not say: a few Swift
//        boolean expressions, decoded, checked against the names the test has and parsed, and asked again with what
//        was wrong, up to the call's rounds.
//  PIN:  THE SCHEMA IS ADVICE. A host pastes it into the prompt; every answer is decoded and checked here.
//  PIN:  AN ANSWER THAT NEVER COMES RIGHT IS LEFT OUT, NOT GUESSED. The action's test then checks only that it
//        ends without a failure, and a note says so; a wrong expectation would fail a test the app passes.

import Foundation
import GraniteAgents

struct ExpectAsk: Sendable {
    let model: any AgentHostModel
    let rounds: Int
    let note: @Sendable (String) -> Void

    private struct Answer: Decodable { let expectations: [String] }

    static let schema = Data(#"{"type":"object","required":["expectations"],"properties":{"expectations":{"type":"array","maxItems":3,"items":{"type":"string","description":"one Swift boolean expression over root.<service>.state and the action's arguments"}}}}"#.utf8)

    /// The expectations for `plan`'s undetermined statements and the round they came right in; nil when no round did.
    func ask(page: PageInfo, plan: PageTestsEmitter.ActionPlan, index: AppIndex) async -> (expectations: [String], rounds: Int)? {
        let user = ExpectPrompts.user(page: page, plan: plan, index: index)
        var prompt = user
        for round in 1...max(1, rounds) {
            var problems: [String] = []
            var said: [String] = []
            do {
                let data = try await model.object(schema: Self.schema, system: ExpectPrompts.system, user: prompt, maxTokens: 400, seconds: 90)
                if let answer = try? JSONDecoder().decode(Answer.self, from: data) {
                    said = answer.expectations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    problems = Self.check(said, plan: plan, index: index)
                } else {
                    problems.append("the answer was not one JSON object {\"expectations\": [\"…\"]}")
                }
            } catch {
                problems.append("\(error)")
            }
            if problems.isEmpty, !said.isEmpty {
                return (Array(said.prefix(3)).map { "#expect(\($0))" }, round)
            }
            if said.isEmpty, problems.isEmpty { problems.append("it says nothing: give at least one expression") }
            note("\(page.name).\(plan.action.name): round \(round), \(problems[0].prefix(90))")
            prompt = user + "\n\nYour last answer was:\n" + said.joined(separator: "\n") + "\n\nWhat was wrong with it:\n"
                + problems.map { "- " + $0 }.joined(separator: "\n") + "\n\nAnswer again, fixed."
        }
        return nil
    }

    /// What is wrong with `expectations`: each must be one pure boolean expression over names the test has, and parse.
    static func check(_ expectations: [String], plan: PageTestsEmitter.ActionPlan, index: AppIndex) -> [String] {
        var problems: [String] = []
        let arguments = Set(plan.action.parameters.map(\.name))
        for expression in expectations.prefix(3) {
            if expression.contains("\n") || expression.contains(";") { problems.append("`\(expression)` is more than one expression"); continue }
            if expression.range(of: #"\b(try|await)\b"#, options: .regularExpression) != nil { problems.append("`\(expression)` has try or await: say a fact, not a call"); continue }
            if expression.range(of: #"(^|[^=!<>])=($|[^=])"#, options: .regularExpression) != nil { problems.append("`\(expression)` assigns: compare with == instead"); continue }
            for word in ["fatalError", "print(", "TODO", "<#"] where expression.contains(word) { problems.append("`\(expression)` has \(word)") }
            var roots = 0
            for match in SwiftText.groups(#"\broot\.(\w+)(?:\.state\.(\w+))?"#, in: expression) {
                roots += 1
                guard let service = index.services.first(where: { $0.relay == match[1] }) else {
                    problems.append("`root.\(match[1])` is no service: the services are \(index.services.map { "root." + $0.relay }.joined(separator: ", "))")
                    continue
                }
                if match[2].isEmpty {
                    problems.append("`\(expression)` reads root.\(match[1]) but not its state: write root.\(match[1]).state.<field>")
                } else if service.field(match[2]) == nil {
                    problems.append("\(service.name)'s state has no `\(match[2])`: it has \(service.fields.map(\.name).joined(separator: ", "))")
                }
            }
            if roots == 0 {
                let named = SwiftText.matches(#"\b([a-z]\w*)\b"#, in: expression).filter { arguments.contains($0) }
                if named.isEmpty { problems.append("`\(expression)` checks nothing the action changes: read root.<service>.state") }
            }
            if let failure = parse(expression, arguments: plan.action.parameters) { problems.append("`\(expression)` does not parse: \(failure)") }
        }
        return problems
    }

    /// The parser's complaint about `expression` as a test would hold it, or nil when it parses.
    static func parse(_ expression: String, arguments: [SwiftParameter]) -> String? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tests-expect-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Expectation.swift")
        let parameters = (["root: Root"] + arguments.map { "\($0.name): \($0.type)" }).joined(separator: ", ")
        let source = "func check(\(parameters)) -> Bool {\n    return \(expression)\n}\n"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(source.utf8).write(to: file)
            return try SwiftParse.check([file])?.replacingOccurrences(of: file.path, with: "Expectation.swift")
        } catch {
            return nil
        }
    }
}
