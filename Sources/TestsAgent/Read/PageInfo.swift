//  WHAT: One page of the app, a `GraniteComponent`, read the way its code says it: the services it reads through
//        relays, the inputs it is made with, its title, and its actions (`+Actions`: what a tap runs).

import Foundation

struct PageInfo: Sendable {
    /// `RecipeList`.
    var name: String
    var folder: URL
    /// Its relays: the name it reads a service by, and the service.
    var relays: [Relay]
    /// What it is made with: `init(recipe: Recipe)`, or its `let` inputs.
    var inputs: [SwiftParameter]
    var actions: [ActionInfo]
    /// The title it shows: `.navigationTitle("Recipes")`.
    var title: String?
    /// The modules its files import beside Granite's and Apple's.
    var imports: [String]

    struct Relay: Sendable, Equatable {
        var name: String
        var service: String
    }

    func action(_ name: String) -> ActionInfo? { actions.first { $0.name == name } }
    func relay(_ name: String) -> Relay? { relays.first { $0.name == name } }
}
