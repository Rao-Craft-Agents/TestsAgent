import Foundation

/// One parameter of a function: `_ id: Int`, `page: Int = 1`, `post: Post? = nil`.
struct SwiftParameter: Sendable, Equatable {
    /// The argument label a call writes; nil for `_`.
    var label: String?
    var name: String
    var type: String
    var defaultValue: String?

    init?(_ text: String) {
        guard let colon = SwiftText.split(text, on: ":").first.flatMap({ text.range(of: $0) }).map({ $0.upperBound }),
              colon < text.endIndex, text[colon] == ":" else { return nil }
        let names = text[..<colon].split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "` ")) }
        var rest = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        if let equals = SwiftText.split(rest, on: "=").first, equals != rest {
            defaultValue = String(rest.dropFirst(equals.count)).trimmingCharacters(in: CharacterSet(charactersIn: "= "))
            rest = equals
        }
        guard let last = names.last, !last.isEmpty else { return nil }
        name = last
        label = names.count > 1 ? (names[0] == "_" ? nil : names[0]) : last
        type = rest.replacingOccurrences(of: "@escaping ", with: "").replacingOccurrences(of: "@Sendable ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    init(label: String?, name: String, type: String, defaultValue: String? = nil) {
        self.label = label; self.name = name; self.type = type; self.defaultValue = defaultValue
    }
}
