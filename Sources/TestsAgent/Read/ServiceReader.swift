//  WHAT: The app's services, each read from its folder: the state's fields and store key from its center, the
//        writer's kinds, the ticketed entries and the reducers they send, each reducer's write, loading key and
//        other sets, the Ops' cases, and the helpers that only write through `set`.

import Foundation

enum ServiceReader {
    static let standardModules: Set<String> = ["Foundation", "Granite", "GraniteAgents", "SwiftUI", "Combine", "AppKit", "UIKit", "os", "Observation"]

    /// Every service in the app's code, with the names the app's root gives their relays.
    static func services(in files: [SourceFile]) -> [ServiceInfo] {
        let rootRelays = Self.rootRelays(in: files)
        var found: [ServiceInfo] = []
        for file in files {
            for name in SwiftText.matches(#"^\s*(?:public\s+)?(?:final\s+)?struct\s+(\w+)\s*:\s*[^{]*\bGraniteService\b"#, in: file.text) {
                let folder = file.url.deletingLastPathComponent()
                let own = files.filter { $0.url.path.hasPrefix(folder.path + "/") }
                found.append(read(name, folder: folder, files: own, relay: rootRelays[name]))
            }
        }
        return found.sorted { $0.name < $1.name }
    }

    /// The relays the app's root holds: service type to the name it goes by.
    static func rootRelays(in files: [SourceFile]) -> [String: String] {
        guard let root = files.first(where: { $0.text.contains("final class AppRoot") }) else { return [:] }
        var relays: [String: String] = [:]
        for match in SwiftText.groups(#"@Relay(?:\([^)]*\))?\s+(?:private\s+|public\s+)?var\s+(\w+)\s*:\s*(\w+)"#, in: root.text) {
            relays[match[2]] = match[1]
        }
        return relays
    }

    static func read(_ name: String, folder: URL, files: [SourceFile], relay: String?) -> ServiceInfo {
        let base = name.hasSuffix("Service") && name.count > 7 ? String(name.dropLast(7)) : name
        var service = ServiceInfo(name: name, base: base, folder: folder, relay: relay ?? Naming.lowerFirst(base),
                                  fields: [], persistKey: nil, centerFile: nil, kinds: [], works: [], ops: [], imports: [])
        var events: [(verb: String, type: String)] = []
        var imports: [String] = []
        for file in files {
            imports += SourceFiles.imports(of: file.text)
            if let body = SwiftText.body(of: #"^\s*(?:public\s+)?struct\s+State\s*:\s*[^{]*\b(?:GraniteState|TransientState)\b"#, in: file.text) {
                service.fields = SwiftText.topLevelLines(body).compactMap(SwiftProperty.init)
                service.centerFile = file.url
                service.persistKey = SwiftText.matches(#"@Store\(\s*persist:\s*"([^"]+)""#, in: file.text).first
                events = SwiftText.groups(#"@Event(?:\([^)]*\))?\s+(?:public\s+)?var\s+(\w+)\s*:\s*(\w+)\.Reducer"#, in: file.text)
                    .map { ($0[1], $0[2]) }.filter { $0.0 != "set" }
            }
            if let body = SwiftText.body(of: #"^\s*(?:public\s+)?enum\s+Kind\s*:"#, in: file.text), file.text.contains("struct Set") {
                service.kinds = SwiftText.topLevelLines(body).filter { $0.hasPrefix("case ") }.flatMap { line in
                    SwiftText.split(String(line.dropFirst(5)), on: ",").map(Self.kindCase)
                }
            }
            if file.text.contains("static func apply("), file.text.contains("\(name).Set.Meta.Kind") || file.text.contains("Set.Meta.Kind") {
                service.ops = Self.opsCases(in: file.text)
            }
        }
        service.imports = Array(Set(imports).subtracting(standardModules)).sorted()

        // The entries: functions of the service that send one of its events.
        let functions = files.filter { $0.text.contains("extension \(name)") || $0.text.contains("struct \(name)") }
            .flatMap { SwiftText.functions(in: $0.text) }
        for function in functions where !function.isStatic && !function.body.contains(".send(") && function.name != "set" {
            let lines = SwiftText.topLevelLines(function.body)
            guard lines.count == 1, let call = Self.setCalls(in: lines[0].hasPrefix("self.") ? lines[0] : "self." + lines[0], owner: "self").first else { continue }
            service.helpers.append(Helper(name: function.name, parameters: function.parameters, set: call))
        }
        for event in events {
            guard let entry = functions.first(where: { !$0.isStatic && $0.body.contains("center.\(event.verb).send(") }) else { continue }
            guard let reducer = files.first(where: { $0.text.range(of: #"struct\s+\#(event.type)\s*:\s*GraniteReducer"#, options: .regularExpression) != nil }) else { continue }
            service.works.append(Self.work(event.verb, type: event.type, entry: entry, reducer: reducer.text, service: service))
        }
        return service
    }

    static func kindCase(_ text: String) -> KindCase {
        let name = String(text.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "`" }).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        let rest = text.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("("), rest.hasSuffix(")") { return KindCase(name: name, payload: String(rest.dropFirst().dropLast())) }
        return KindCase(name: name, payload: nil)
    }

    static func work(_ verb: String, type: String, entry: SwiftFunction, reducer text: String, service: ServiceInfo) -> WorkInfo {
        let functions = SwiftText.functions(in: text)
        let reduce = functions.first { $0.name == "reduce" }?.body ?? ""
        let effect = functions.first { $0.name == "effect" }?.body ?? ""
        let work = functions.filter { $0.isStatic }.map(\.body).joined(separator: "\n")
        let loading = SwiftText.matches(#"state\.loading\s*=\s*"([^"]*)""#, in: reduce).first
        let owner = SwiftText.matches(#"let\s+(\w+)\s*=\s*Live\.service\("#, in: effect).first ?? "service"
        var write = WorkWrite.none
        var sets: [SetCall] = []
        for call in Self.setCalls(in: effect, owner: owner) {
            // What every piece of work sets about itself: in flight, failed, cleared.
            if ["loading", "lastError", "failed", "clear"].contains(call.kind) { continue }
            if service.field(call.kind) != nil, write == .none { write = .replace(call.kind); continue }
            if call.kind.hasPrefix("append"), let field = service.fields.first(where: { "append" + Naming.upperFirst($0.name) == call.kind }) {
                if write == .none { write = .append(field.name) }
                continue
            }
            if service.field(call.kind) != nil { continue }
            sets.append(call)
        }
        var names: [String: String] = [:]
        for match in SwiftText.groups(#"let\s+(\w+)\s*=\s*meta\.(\w+)"#, in: effect) { names[match[1]] = match[2] }
        return WorkInfo(verb: verb, typeName: type, entry: entry, loadingKey: loading, write: write,
                        text: effect + "\n" + work, sets: sets, payloadNames: names)
    }

    /// `owner.set(.kind(a, label: b))` calls in `text`.
    static func setCalls(in text: String, owner: String) -> [SetCall] {
        var calls: [SetCall] = []
        let marker = "\(owner).set(."
        var searchFrom = text.startIndex
        while let found = text.range(of: marker, range: searchFrom..<text.endIndex) {
            searchFrom = found.upperBound
            let kind = String(text[found.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            let after = text.index(found.upperBound, offsetBy: kind.count)
            var arguments: [String] = []
            if after < text.endIndex, text[after] == "(", let (inside, _) = SwiftText.parenthesized(text, from: after) {
                arguments = SwiftText.split(inside, on: ",").map { argument in
                    if let colon = argument.firstIndex(of: ":"), argument[..<colon].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                        return argument[argument.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    }
                    return argument
                }
            }
            if !kind.isEmpty { calls.append(SetCall(kind: kind, arguments: arguments)) }
        }
        return calls
    }

    /// The cases of an Ops `apply`'s switch, each with its bindings and its plain assignments to the state.
    static func opsCases(in text: String) -> [OpsCase] {
        guard let body = SwiftText.body(of: #"static\s+func\s+apply\("#, in: text) else { return [] }
        var cases: [OpsCase] = []
        var current: OpsCase?
        for raw in body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("case ."), line.hasSuffix(":") {
                if let done = current { cases.append(done) }
                let pattern = String(line.dropFirst(5).dropLast())
                current = OpsCase(kinds: SwiftText.matches(#"\.(\w+)"#, in: pattern),
                                  bindings: SwiftText.matches(#"let\s+(\w+)"#, in: pattern), assignments: [])
            } else if line.hasPrefix("default") {
                if let done = current { cases.append(done) }
                current = nil
            } else if let match = SwiftText.groups(#"^state\.(\w+)\s*=\s*(.+)$"#, in: line).first, !line.contains("==") {
                current?.assignments.append(.init(field: match[1], value: match[2]))
            }
        }
        if let done = current { cases.append(done) }
        return cases
    }
}
