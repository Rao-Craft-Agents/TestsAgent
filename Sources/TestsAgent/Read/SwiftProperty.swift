import Foundation

/// A stored property: `var recipes: [Recipe] = []`, `let id: UUID`.
struct SwiftProperty: Sendable, Equatable {
    var name: String
    var type: String?
    var defaultValue: String?
    var isLet: Bool

    init?(_ line: String) {
        let pattern = #"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|static|nonisolated|lazy|weak)(?:\(set\))?\s+)*(var|let)\s+(`?\w+`?)\s*(?::\s*([^={]+?))?\s*(?:=\s*(.+))?$"#
        guard let match = SwiftText.groups(pattern, in: line).first else { return nil }
        // A computed property (`var x: Int { … }`) is not stored.
        if line.hasSuffix("{") || (match[4].isEmpty && line.contains("{")) { return nil }
        if line.contains("static ") { return nil }
        isLet = match[1] == "let"
        name = match[2].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        type = match[3].isEmpty ? nil : match[3].trimmingCharacters(in: .whitespaces)
        defaultValue = match[4].isEmpty ? nil : match[4].trimmingCharacters(in: .whitespaces)
    }
}
