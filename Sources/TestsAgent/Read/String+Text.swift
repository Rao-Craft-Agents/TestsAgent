//  WHAT: Small words for text: an empty string as nil, a line kept only when it applies.

import Foundation

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// The string when `condition` holds, nil otherwise: a line written only when it applies.
    func onlyIf(_ condition: Bool) -> String? { condition ? self : nil }
}
