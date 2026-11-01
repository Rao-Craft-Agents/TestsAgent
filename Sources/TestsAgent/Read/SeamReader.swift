//  WHAT: The seams a piece of work sends through: each call of a client's endpoint read back from its receiver
//        (`RecipeClient.current.recipes(`) to the declaration it names, and whether a test may assign it.
//  PIN:  A RECEIVER THAT IS NOT A STATIC OR THE ROOT'S IS UNREAD. A client made in the work, or held by a local,
//        cannot be replaced by a test: the work is left out, never tested against a live server.

import Foundation

enum SeamReader {
    /// The endpoint calls in `text` (a reducer's effect and work), each read back to its seam among `files`.
    static func calls(in text: String, clients: [ClientInfo], files: [SourceFile]) -> (calls: [EndpointCall], unread: [String]) {
        var calls: [EndpointCall] = [], unread: [String] = []
        for client in clients {
            for endpoint in client.endpoints {
                let pattern = #"([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\.\#(endpoint.name)\("#
                for receiver in SwiftText.matches(pattern, in: text) {
                    if let seam = seam(receiver, client: client, files: files) {
                        let call = EndpointCall(seam: seam, endpoint: endpoint.name)
                        if !calls.contains(call) { calls.append(call) }
                    } else if !unread.contains(receiver) {
                        unread.append(receiver)
                    }
                }
            }
        }
        return (calls, unread)
    }

    /// The seam `receiver` names, when it is a static value or the app root's, declared in `files`.
    static func seam(_ receiver: String, client: ClientInfo, files: [SourceFile]) -> Seam? {
        let parts = receiver.split(separator: ".").map(String.init)
        guard parts.count >= 2, let owner = parts.first, owner.first?.isUppercase == true else { return nil }
        if parts.count == 2 {
            guard let declaration = declaration(of: parts[1], in: owner, files: files, isStatic: true) else { return nil }
            let holdsClient = declaration.type?.contains(client.client) == true || declaration.value?.contains(client.client) == true
                || owner == client.client
            guard holdsClient else { return nil }
            return Seam(path: receiver, client: client.client, isAssignable: declaration.isAssignable, isInstance: false)
        }
        if parts.count == 3, parts[1] == "shared", let declaration = declaration(of: parts[2], in: owner, files: files, isStatic: false) {
            let holdsClient = declaration.type?.contains(client.client) == true || declaration.value?.contains(client.client) == true
            guard holdsClient else { return nil }
            return Seam(path: receiver, client: client.client, isAssignable: declaration.isAssignable, isInstance: true)
        }
        return nil
    }

    struct Declaration {
        var type: String?
        var value: String?
        var isAssignable: Bool
    }

    /// `name`'s declaration one level inside `owner` (its type, an extension of it), static or not.
    static func declaration(of name: String, in owner: String, files: [SourceFile], isStatic: Bool) -> Declaration? {
        let opener = #"^\s*(?:@\w+\s+)*(?:public\s+|internal\s+)?(?:final\s+)?(?:extension|enum|struct|class|actor)\s+\#(owner)\b[^{]*\{"#
        for file in files {
            guard let regex = try? NSRegularExpression(pattern: opener, options: [.anchorsMatchLines]) else { continue }
            for match in regex.matches(in: file.text, range: NSRange(file.text.startIndex..., in: file.text)) {
                guard let range = Range(match.range, in: file.text), let open = file.text[range].lastIndex(of: "{"),
                      let end = SwiftText.close(file.text, from: open) else { continue }
                let body = String(file.text[file.text.index(after: open)..<file.text.index(before: end)])
                let pattern = #"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|nonisolated\(unsafe\)|nonisolated|static|lazy)(?:\(set\))?\s+)*(var|let)\s+\#(name)\b\s*(?::\s*([^={]+?))?\s*(=\s*.+|\{.*)?$"#
                for line in SwiftText.topLevelLines(body) where line.contains(name) {
                    guard let found = SwiftText.groups(pattern, in: line).first else { continue }
                    if isStatic != line.contains("static ") { continue }
                    if line.contains("private(set)") || line.contains("fileprivate(set)") {
                        return Declaration(type: found[2].nilIfEmpty, value: found[3].nilIfEmpty, isAssignable: false)
                    }
                    let tail = found[3]
                    if found[1] == "let" { return Declaration(type: found[2].nilIfEmpty, value: tail.nilIfEmpty, isAssignable: false) }
                    if tail.hasPrefix("{") {
                        // Computed: assignable only with a setter.
                        let block = Self.block(of: line, in: body)
                        return Declaration(type: found[2].nilIfEmpty, value: block, isAssignable: block.contains("set {") || block.contains("set("))
                    }
                    return Declaration(type: found[2].nilIfEmpty, value: tail.nilIfEmpty, isAssignable: true)
                }
            }
        }
        return nil
    }

    /// The block a computed property's declaration on `line` opens, from `body`.
    private static func block(of line: String, in body: String) -> String {
        guard let start = body.range(of: line), let open = body[start.lowerBound...].firstIndex(of: "{"),
              let end = SwiftText.close(body, from: open) else { return line }
        return String(body[open..<end])
    }
}
