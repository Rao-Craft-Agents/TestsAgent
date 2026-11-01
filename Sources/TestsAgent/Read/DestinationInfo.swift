//  WHAT: The app's destinations, as `granite`'s navigation writes them: `enum AppDestination`, a case a place,
//        each with its title and its page, and whether a launch may ask for one (`-destination <case>`).

import Foundation

struct DestinationInfo: Sendable, Equatable {
    /// The case: `recipes`.
    var name: String
    /// What the tab bar and the sidebar call it.
    var title: String?
    /// The page it shows: `RecipeList`.
    var page: String?
}
