import Foundation

/// One case of an Ops `apply`: the kinds it matches, the names it binds, and what it assigns to the state.
struct OpsCase: Sendable {
    var kinds: [String]
    var bindings: [String]
    var assignments: [Assignment]

    struct Assignment: Sendable, Equatable {
        var field: String
        var value: String
    }
}
