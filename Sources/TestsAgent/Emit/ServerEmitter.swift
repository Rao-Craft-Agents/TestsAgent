//  WHAT: A client package's server, as the tests play it: one `HTTPTransport` that answers every endpoint the
//        package declares from its preview values, a page at a time, as the test's scenario says, and keeps every
//        request. What a client gets when `mocks` has not written it a `.mock()`.
//  PIN:  NOTHING LEAVES THE PROCESS. The client the tests make sends through this transport alone; a request it
//        has no answer for is a 404, never a fall-through to the network.
//  PIN:  PAGES DIFFER. The first three pages carry two items each with ids of their own, then pages are empty, so a
//        test sees a second page added and paging end.

import Foundation

struct ServerEmitter {
    let client: ClientInfo
    let previews: Set<String>
    let enums: [String: [String]]

    /// `RecipeServer`: the client's name with `Server` for `Client`.
    var type: String { Self.type(of: client) }
    /// `recipeServer`: what the test root calls it.
    var property: String { Naming.lowerFirst(type) }

    static func type(of client: ClientInfo) -> String {
        (client.client.hasSuffix("Client") ? String(client.client.dropLast(6)) : client.client) + "Server"
    }

    /// How each endpoint is answered, or why it cannot be.
    enum Answer {
        case nothing
        case bytes
        case value(String)
        case list(element: String, paged: Bool)
        case wrapped(type: String, field: String, element: String, paged: Bool)
        case unanswerable(String)
    }

    func answer(_ endpoint: EndpointInfo) -> Answer {
        guard let response = endpoint.response else { return .nothing }
        if response == "Data" || response == "String" { return .bytes }
        if let element = Samples.element(of: response) {
            guard sample(element) != nil else { return .unanswerable("\(element) has no preview to answer with") }
            return .list(element: element, paged: endpoint.pageQuery != nil)
        }
        if let model = client.types[response], !model.isEnum {
            if endpoint.pageQuery != nil, model.hasPreview,
               let list = model.fields.first(where: { !$0.isLet && Samples.element(of: $0.type) != nil }),
               let element = Samples.element(of: list.type), sample(element) != nil {
                return .wrapped(type: response, field: list.name, element: element, paged: true)
            }
        }
        if let value = sample(response) { return .value(value) }
        return .unanswerable("\(response) has no preview to answer with")
    }

    private func sample(_ type: String) -> String? {
        Samples.value(type, name: "value", previews: previews.union(client.types.values.filter(\.hasPreview).map(\.name)), enums: enums)
    }

    func file() -> String {
        var code = Code()
        code.lines(["import Foundation", "import \(client.module)", ""])
        code.doc("\(client.module)'s server, as the tests play it: every endpoint answered from the package's preview values, a page at a time, as the scenario says, and every request kept. Nothing leaves the process.")
        code.open("final class \(type): HTTPTransport, @unchecked Sendable {")
        code.lines(["let scenario: BackendScenario", "private let lock = NSLock()", "private var sent: [URLRequest] = []", ""])
        code.open("init(_ scenario: BackendScenario) {")
        code.line("self.scenario = scenario")
        code.close()
        code.line()
        code.line("/// A client of the API that sends through this server and never tries again.")
        code.open("var client: \(client.client) {")
        let base = Naming.escaped(client.baseURL ?? "https://example.com")
        code.line("\(client.client)(baseURL: URL(string: \"\(base)\")!, tokens: MemoryTokenStore(), transport: self, retry: .never)")
        code.close()
        code.line()
        code.line("/// Every request sent, in order.")
        code.line("var requests: [URLRequest] { lock.withLock { sent } }")
        code.line()
        code.line("/// Whether a `method` request was sent to `path`, where a `{name}` segment matches any one segment.")
        code.open("func received(_ method: String, _ path: String) -> Bool {")
        code.line("requests.contains { ($0.httpMethod ?? \"GET\") == method && Self.matches(path, $0.url?.path ?? \"\") }")
        code.close()
        code.line()
        code.open("func send(_ request: URLRequest) async throws -> HTTPResponse {")
        code.line("lock.withLock { sent.append(request) }")
        code.line("if scenario == .slow { try await Task.sleep(for: .milliseconds(400)) }")
        code.open("if scenario == .failing {")
        code.line("return HTTPResponse(status: 500, headers: [\"Content-Type\": \"application/json\"],")
        code.line("                    body: Data(#\"{\"error\": \"The server is down for maintenance.\"}\"#.utf8))")
        code.close()
        code.lines(["let method = request.httpMethod ?? \"GET\"", "let path = request.url?.path ?? \"/\""])
        if client.endpoints.contains(where: { $0.pageQuery != nil }) { code.line("let page = Self.page(of: request)") }
        for endpoint in client.endpoints {
            let answer = answer(endpoint)
            if case .unanswerable = answer { continue }
            code.open("if method == \"\(endpoint.method)\", Self.matches(\"\(Naming.escaped(endpoint.path))\", path) {")
            switch answer {
            case .nothing:
                code.line("return HTTPResponse(status: 204)")
            case .bytes:
                code.line("return HTTPResponse(status: 200, headers: [\"Content-Type\": \"text/plain\"], body: Data(\"sample\".utf8))")
            case .value(let value):
                code.line("return try Self.json(\(value))")
            case .list(_, let paged):
                code.line("return try Self.json(scenario == .empty ? [] : Self.\(endpoint.name)Page(\(paged ? "page" : "1")))")
            case .wrapped(let type, let field, _, let paged):
                code.line("var value = \(type).preview")
                code.line("value.\(Naming.member(field)) = scenario == .empty ? [] : Self.\(endpoint.name)Page(\(paged ? "page" : "1"))")
                code.line("return try Self.json(value)")
            case .unanswerable:
                break
            }
            code.close()
        }
        code.line("return HTTPResponse(status: 404, headers: [\"Content-Type\": \"application/json\"], body: Data(#\"{\"error\": \"Not found.\"}\"#.utf8))")
        code.close()
        for endpoint in client.endpoints {
            let element: String, paged: Bool
            switch answer(endpoint) {
            case .list(let e, let p): element = e; paged = p
            case .wrapped(_, _, let e, let p): element = e; paged = p
            default: continue
            }
            code.line()
            if paged {
                code.line("/// Page `page` of `\(endpoint.name)`: two items on each of the first three pages, then none, so paging ends.")
            } else {
                code.line("/// What `\(endpoint.name)` lists: two items.")
            }
            code.open("static func \(endpoint.name)Page(_ page: Int) -> [\(element)] {")
            code.line("guard (1...3).contains(page) else { return [] }")
            code.lines(items(element))
            code.close()
        }
        if client.endpoints.contains(where: { $0.pageQuery != nil }) {
            let names = Set(client.endpoints.compactMap(\.pageQuery)).sorted()
            code.line()
            code.line("/// The page a request asks for; the first when it names none.")
            code.open("private static func page(of request: URLRequest) -> Int {")
            code.line("guard let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return 1 }")
            code.line("return items.first { \(names.map { "$0.name == \"\($0)\"" }.joined(separator: " || ")) }?.value.flatMap(Int.init) ?? 1")
            code.close()
        }
        code.line()
        code.line("/// Whether `path` is `template`, a `{name}` segment matching any one segment.")
        code.open("private static func matches(_ template: String, _ path: String) -> Bool {")
        code.line("let expected = template.split(separator: \"/\"), actual = path.split(separator: \"/\")")
        code.line("guard expected.count == actual.count else { return false }")
        code.line("return zip(expected, actual).allSatisfy { $0.hasPrefix(\"{\") || $0 == $1 }")
        code.close()
        code.line()
        code.line("/// `value` as the API writes it.")
        code.open("private static func json(_ value: some Encodable) throws -> HTTPResponse {")
        let encoder = client.coding.map { "\($0).encoder()" } ?? "JSONEncoder()"
        code.line("HTTPResponse(status: 200, headers: [\"Content-Type\": \"application/json\"], body: try \(encoder).encode(value))")
        code.close()
        code.close()
        return code.text
    }

    /// The lines that answer a page's two items: the element's sample, each with an id of its own when it has one.
    private func items(_ element: String) -> [String] {
        let number = "(page - 1) * 2 + index"
        switch element {
        case "Int", "Int64", "Int32": return ["return (1...2).map { index in \(number) }"]
        case "String": return ["return (1...2).map { index in \"sample \\(\(number))\" }"]
        default: break
        }
        let sample = sample(element) ?? "\(element).preview"
        let value: String
        switch client.types[element]?.idType?.trimmingCharacters(in: CharacterSet(charactersIn: "?")) {
        case "Int", "Int64", "Int32", "UInt": value = number
        case "String": value = "\"\\(\(number))\""
        case "UUID": value = "UUID(uuidString: String(format: \"00000000-0000-0000-0000-%012d\", \(number)))!"
        default: return ["return Array(repeating: \(sample), count: 2)"]
        }
        return ["return (1...2).map { index in", "    var item = \(sample)", "    item.id = \(value)", "    return item", "}"]
    }
}
