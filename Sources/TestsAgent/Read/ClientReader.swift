//  WHAT: The client packages of an app, read off the Swift `network` wrote into `Packages/<Kit>`: the client
//        type, its coding, each endpoint's method, path, answer and page query, the models' fields and previews,
//        and a `mocks` `.mock()` beside them.

import Foundation

enum ClientReader {
    /// Every client package in the app's `Packages` folder (each `network` wrote: it has an `api.json`).
    static func clients(in root: URL) -> [ClientInfo] {
        AppProject.contents(of: root.appendingPathComponent("Packages")).compactMap(read)
    }

    static func read(_ folder: URL) -> ClientInfo? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.appendingPathComponent("api.json").path) else { return nil }
        let record = (try? Data(contentsOf: folder.appendingPathComponent("api.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let module = (record["name"] as? String) ?? folder.lastPathComponent
        let sources = folder.appendingPathComponent("Sources/\(module)")
        let files = SourceFiles.swift(under: sources, skipping: [".build"])
        guard let client = files.lazy.compactMap({ SwiftText.matches(#"public\s+(?:final\s+)?(?:class|actor|struct)\s+(\w+Client)\b"#, in: $0.text).first }).first else {
            return nil
        }
        let coding = files.lazy.compactMap { SwiftText.matches(#"public\s+enum\s+(\w+Coding)\b"#, in: $0.text).first }.first
        var endpoints: [EndpointInfo] = []
        var types: [String: ModelType] = [:]
        var mock: MockSupport?
        for file in files {
            if file.url.path.contains("/Endpoints/") { endpoints += Self.endpoints(in: file.text) }
            if file.url.path.contains("/Models/") {
                for type in Self.types(in: file.text) { types[type.name] = type }
            }
            if file.text.contains("static func mock(") {
                let cases = files.lazy.compactMap { file -> [String]? in
                    guard let body = SwiftText.body(of: #"^\s*public\s+enum\s+MockScenario\b"#, in: file.text) else { return nil }
                    return Self.cases(in: body)
                }.first ?? []
                if !cases.isEmpty {
                    mock = MockSupport(scenarios: cases, takesLatency: file.text.range(of: #"static func mock\([^)]*latency:"#, options: .regularExpression) != nil)
                }
            }
        }
        return ClientInfo(module: module, folder: folder, client: client, coding: coding, baseURL: record["baseURL"] as? String,
                          endpoints: endpoints.sorted { $0.name < $1.name }, types: types, mock: mock)
    }

    /// The endpoints an `Endpoints/` file declares: a method that sends a `Request` to a path.
    static func endpoints(in text: String) -> [EndpointInfo] {
        let functions = SwiftText.functions(in: text)
        let names = Set(functions.map(\.name))
        return functions.compactMap { function in
            guard let request = SwiftText.groups(#"Request<(.+?)>\(\s*\.(\w+)\s*,\s*"([^"]+)""#, in: function.body).first else { return nil }
            let response = request[1] == "NoContent" ? nil : request[1]
            var pageQuery: String?
            for pair in SwiftText.groups(#""([\w.-]+)"\s*:\s*(\w+)"#, in: function.body) where pair[2].lowercased().contains("page") {
                pageQuery = pair[1]
                break
            }
            return EndpointInfo(name: function.name, method: request[2].uppercased(), path: request[3], response: response,
                                parameters: function.parameters, pageQuery: pageQuery, isPaged: names.contains(function.name + "Pages"))
        }
    }

    /// The types a `Models/` file declares.
    static func types(in text: String) -> [ModelType] {
        var found: [ModelType] = []
        for match in SwiftText.groups(#"^(?:public\s+)?(struct|enum)\s+(\w+)\b[^{]*\{"#, in: text) {
            let name = match[2]
            let pattern = #"^(?:public\s+)?(?:struct|enum)\s+"# + name + #"\b"#
            guard let body = SwiftText.body(of: pattern, in: text) else { continue }
            let isEnum = match[1] == "enum"
            found.append(ModelType(name: name, isEnum: isEnum,
                                   fields: isEnum ? [] : SwiftText.topLevelLines(body).compactMap(SwiftProperty.init),
                                   cases: isEnum ? cases(in: body) : [],
                                   hasPreview: text.contains("static let preview: \(name)") || text.contains("static var preview: \(name)")))
        }
        return found
    }

    /// The case names one level inside an enum's body.
    static func cases(in body: String) -> [String] {
        SwiftText.topLevelLines(body).filter { $0.hasPrefix("case ") }.flatMap { line in
            SwiftText.split(String(line.dropFirst(5)), on: ",").map { piece in
                String(piece.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "`" }).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            }
        }.filter { !$0.isEmpty }
    }
}
