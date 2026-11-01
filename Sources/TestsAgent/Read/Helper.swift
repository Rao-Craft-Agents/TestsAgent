import Foundation

/// A helper of a service that is one `set` of its writer: what a page calls it with becomes the kind's payload.
struct Helper: Sendable {
    var name: String
    var parameters: [SwiftParameter]
    /// The set it makes, its arguments in the helper's parameter names.
    var set: SetCall
}
