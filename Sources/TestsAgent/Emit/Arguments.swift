//  WHAT: What a test passes a function: a sample for each parameter without a default, a page number for a page.

import Foundation

struct Arguments {
    /// The call's arguments, as written between its parentheses.
    var text: String
    /// Each parameter's value, by its name.
    var values: [String: String]
    /// Whether a parameter carries a page number.
    var hasPage: Bool

    /// Arguments for `parameters`, page `page`; nil when a parameter that must be given has no sample.
    static func make(_ parameters: [SwiftParameter], page: Int, index: AppIndex) -> Arguments? {
        var parts: [String] = [], values: [String: String] = [:], hasPage = false
        for parameter in parameters {
            let bare = parameter.type.trimmingCharacters(in: CharacterSet(charactersIn: "? "))
            let isPage = Samples.isPage(parameter.name) && ["Int", "Int64", "Int32", "UInt"].contains(bare)
            if parameter.defaultValue != nil, !isPage { continue }
            guard let value = Samples.value(parameter.type, name: parameter.name, page: page, previews: index.previews, enums: index.enums) else {
                return nil
            }
            hasPage = hasPage || isPage
            values[parameter.name] = value
            parts.append(parameter.label.map { "\($0): \(value)" } ?? value)
        }
        return Arguments(text: parts.joined(separator: ", "), values: values, hasPage: hasPage)
    }
}
