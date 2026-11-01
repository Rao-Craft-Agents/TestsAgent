//  WHAT: What the host's model is told when a page action's outcome is not in the code: the rules of the answer and
//        one example, from a recipe app, never the app being tested.

import Foundation

enum ExpectPrompts {
    static let system = """
        You say what one action of an app's page leaves behind, as Swift boolean expressions a test checks with \
        #expect after the action has run against a mock backend. The test names every service of the app through \
        `root` (`root.recipes.state.selected`) and the action's arguments by their own names. Say only what the \
        action's code makes true; leave out what the code does not say. Write each fact as one expression over those \
        names: compare with == != < > <= >=, or use isEmpty, count, contains, first, last; no assignment, no try, no \
        await, nothing that changes anything. At most three. Answer as JSON: {"expectations": ["…"]}.

        Example. The page RecipeList, the action:
        func browseCooks(recipe: Recipe) async throws {
            layout.select(.cooks)
            layout.show(detail: String(recipe.cookID))
        }
        The services, as the test names them:
        - root.layout (LayoutService): destination AppDestination, detail String?; helpers: select(_ destination: AppDestination) \
        sets destination; show(detail id: String) sets detail
        Answer: {"expectations": ["root.layout.state.destination == .cooks", "root.layout.state.detail == String(recipe.cookID)"]}
        """

    /// The ask for `plan`'s undetermined statements on `page`.
    static func user(page: PageInfo, plan: PageTestsEmitter.ActionPlan, index: AppIndex) -> String {
        let action = plan.action
        let parameters = action.parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
        var lines = ["The page \(page.name), the action:", "func \(action.name)(\(parameters)) async throws {"]
        lines += action.statements.map { "    " + $0 }
        lines.append("}")
        if !plan.bindings.isEmpty { lines.append("What the test passes: " + plan.bindings.map { $0.replacingOccurrences(of: "let ", with: "") }.joined(separator: "; ")) }
        lines.append("The statements whose outcome you say: " + plan.undetermined.joined(separator: "; "))
        lines.append("The services, as the test names them:")
        for relay in page.relays {
            guard let service = index.service(of: relay) else { continue }
            let fields = service.fields.map { "\($0.name) \($0.type ?? "?")" }.joined(separator: ", ")
            var line = "- root.\(service.relay) (\(service.name)), the page's `\(relay.name)`: \(fields)"
            let entries = service.works.map { work -> String in
                let does: String
                switch work.write {
                case .replace(let field): does = "replaces \(field)"
                case .append(let field): does = "adds to \(field)"
                case .none: does = "asks the backend"
                }
                return "\(work.entry.name)(\(work.entry.parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", "))) \(does)"
            }
            if !entries.isEmpty { line += "; its work: " + entries.joined(separator: "; ") }
            lines.append(line)
        }
        lines.append("Say what those statements leave behind.")
        return lines.joined(separator: "\n")
    }
}
