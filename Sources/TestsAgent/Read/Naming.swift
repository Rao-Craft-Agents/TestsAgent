//  WHAT: How names are said: a type's first letter raised or lowered, Swift's keywords escaped, a name in words.

import Foundation

enum Naming {
    static let keywords: Set<String> = ["associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
                                        "inout", "internal", "let", "open", "operator", "private", "protocol", "public", "rethrows",
                                        "static", "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue",
                                        "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return",
                                        "throw", "switch", "where", "while", "as", "Any", "false", "is", "nil", "self", "Self", "super",
                                        "throws", "true", "try", "some", "any"]

    static func upperFirst(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    static func lowerFirst(_ text: String) -> String {
        let characters = Array(text)
        var upper = 0
        while upper < characters.count, characters[upper].isUppercase { upper += 1 }
        if upper == 0 { return text }
        let cut = upper == characters.count || upper == 1 ? upper : upper - 1
        return String(characters[..<cut]).lowercased() + String(characters[cut...])
    }

    /// A member name as code writes it: a keyword in backticks.
    static func member(_ name: String) -> String { keywords.contains(name) ? "`\(name)`" : name }

    /// `RecipeList` → `Recipe List`; `aFailedLoad` → `a failed load`.
    static func words(_ name: String) -> String {
        var out = "", previous: Character?
        for character in name {
            if character.isUppercase, let p = previous, p.isLowercase || p.isNumber { out.append(" ") }
            out.append(character)
            previous = character
        }
        return out
    }

    /// `text` as a Swift string literal's contents.
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
