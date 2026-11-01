import Foundation

/// What a page does, as its `+Actions` file says: `func favor(recipe: Recipe) async throws { … }`.
struct ActionInfo: Sendable {
    var name: String
    var parameters: [SwiftParameter]
    var statements: [String]
    var isAsync: Bool
    var isThrowing: Bool
}
