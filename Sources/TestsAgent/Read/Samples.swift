//  WHAT: A value of a type, said in Swift, for a test to pass: a page number, an id, a model's `preview`, an enum's
//        first case. What has no sample is nil, and the test that would need it is left out with a note.

import Foundation

enum Samples {
    /// A sample of `type` for the parameter `name`; `page` is the page number a page-like parameter takes.
    static func value(_ type: String, name: String, page: Int = 1, previews: Set<String>, enums: [String: [String]],
                      mockIDs: [String: String] = [:], rawValues: [String: String] = [:]) -> String? {
        let type = type.trimmingCharacters(in: .whitespaces)
        if type.hasSuffix("?") { return value(String(type.dropLast()), name: name, page: page, previews: previews, enums: enums, mockIDs: mockIDs, rawValues: rawValues) }
        // An id the mock backend answers (`postId` takes the first post's), and a string an enum is made from.
        if let id = Self.mockID(name: name, type: type, mockIDs: mockIDs) { return id }
        if type == "String", let made = rawValues[name], let first = enums[made]?.first { return "\"\(first)\"" }
        if type.hasPrefix("["), type.hasSuffix("]") {
            let inside = String(type.dropFirst().dropLast())
            if SwiftText.split(inside, on: ":").count == 2 { return "[:]" }
            return value(inside, name: name, page: page, previews: previews, enums: enums).map { "[\($0)]" } ?? "[]"
        }
        let lower = name.lowercased()
        switch type {
        case "Int", "Int64", "Int32", "UInt", "UInt64", "Int16", "UInt32": return isPage(name) ? "\(page)" : "1"
        case "Double", "Float", "CGFloat": return "1.5"
        case "Bool": return "true"
        case "String":
            if lower.hasSuffix("id") { return "\"1\"" }
            if lower.contains("email") { return "\"cook@example.com\"" }
            return "\"sample\""
        case "Date": return "Date(timeIntervalSince1970: 1_767_225_600)"
        case "URL": return "URL(string: \"https://example.com\")!"
        case "UUID": return "UUID(uuidString: \"00000000-0000-0000-0000-000000000001\")!"
        case "Data": return "Data()"
        default: break
        }
        let bare = type.split(separator: ".").last.map(String.init) ?? type
        if previews.contains(bare) { return "\(type).preview" }
        if let first = enums[bare]?.first { return ".\(Naming.member(first))" }
        return nil
    }

    /// The mock's id for a parameter named for a type's id (`postId`, `postID`, `post_id`), when the type is the
    /// mock's and the literal fits the parameter's type.
    static func mockID(name: String, type: String, mockIDs: [String: String]) -> String? {
        let lower = name.lowercased()
        guard lower.hasSuffix("id"), lower.count > 2 else { return nil }
        let stem = String(lower.dropLast(2)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard let literal = mockIDs[stem] else { return nil }
        let quoted = literal.hasPrefix("\"")
        if ["Int", "Int64", "Int32", "UInt", "UInt64"].contains(type) { return quoted ? nil : literal }
        if type == "String" { return quoted ? literal : "\"\(literal)\"" }
        return nil
    }

    /// Whether a parameter carries a page number: `page`, `pageNumber`, `nextPage`.
    static func isPage(_ name: String) -> Bool { name.lowercased().contains("page") }

    /// The element of a list type: `[Recipe]` → `Recipe`, `[Recipe]?` → `Recipe`; nil for anything else.
    static func element(of type: String?) -> String? {
        guard var text = type?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasSuffix("?") { text.removeLast() }
        guard text.hasPrefix("["), text.hasSuffix("]") else { return nil }
        let inside = String(text.dropFirst().dropLast())
        return SwiftText.split(inside, on: ":").count == 2 ? nil : inside
    }

    static func isOptional(_ type: String?) -> Bool { type?.trimmingCharacters(in: .whitespaces).hasSuffix("?") == true }

    /// Whether `text` is a literal a test may compare with as it is: `nil`, `true`, a number, a string, `.ready`, `[]`.
    static func isLiteral(_ text: String) -> Bool {
        text.range(of: #"^(nil|true|false|-?\d+(\.\d+)?|"[^"\\]*"|\.[a-z]\w*|\[\]|\[:\])$"#, options: .regularExpression) != nil
    }
}
