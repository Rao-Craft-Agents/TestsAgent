import Foundation

/// A function as its declaration says it.
struct SwiftFunction: Sendable {
    var name: String
    var parameters: [SwiftParameter]
    var returns: String?
    var isAsync: Bool
    var isThrowing: Bool
    var isStatic: Bool
    var body: String
    /// What stands before `func`: attributes and modifiers.
    var attributes: String
}
