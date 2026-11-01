//  WHAT: Where a test puts a mock: the value a service's work sends through (`RecipeClient.current`,
//        `Backend.recipes`, `AppRoot.shared.client`), found where the work calls a client's endpoint, read back to
//        its declaration, and whether a test can assign it.
//  PIN:  A TEST REPLACES THE VALUE THE WORK READS, NEVER THE WORK. The reducer stays the app's own; only what it
//        sends through answers from the mock. A value a test cannot assign (a `let`, a computed one with no
//        setter) is said in a note with the one-line change that opens it.

import Foundation

struct Seam: Sendable, Equatable {
    /// The expression the work reads: `RecipeClient.current`.
    var path: String
    /// The client type it holds.
    var client: String
    /// Whether a test may assign it.
    var isAssignable: Bool
    /// Whether the assignment is made on the main actor's instance: `AppRoot.shared.client`.
    var isInstance: Bool
}
