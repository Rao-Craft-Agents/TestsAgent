import Foundation

/// A `set(.kind(…))` a piece of work makes: the kind and its arguments, labels taken off.
struct SetCall: Sendable, Equatable {
    var kind: String
    var arguments: [String]
}
