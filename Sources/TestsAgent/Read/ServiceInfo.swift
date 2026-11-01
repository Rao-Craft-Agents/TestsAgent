//  WHAT: One Granite service of the app, read the way its code says it: its state's fields, whether and where it
//        persists, its writer's kinds, its ticketed entries and the work reducer each sends, what each piece of
//        work awaits and writes, and what its Ops do with each kind.
//  PIN:  THE CODE IS THE SPEC. A test asserts what the reducer and the Ops write, read off them: the field a work
//        replaces or appends to, the key it marks while in flight, the assignments of the kind it sets.

import Foundation

struct ServiceInfo: Sendable {
    /// `RecipesService`.
    var name: String
    /// `Recipes`.
    var base: String
    var folder: URL
    /// The name a relay to it goes by: the app root's, else the base's in lowerCamelCase.
    var relay: String
    /// The state's stored fields.
    var fields: [SwiftProperty]
    /// The store's persistence key, when the state is kept between launches.
    var persistKey: String?
    /// The center's file, where the persistence key is.
    var centerFile: URL?
    /// The writer's kinds.
    var kinds: [KindCase]
    var works: [WorkInfo]
    /// What the Ops do with each kind.
    var ops: [OpsCase]
    /// The modules its files import beside Granite's and Apple's.
    var imports: [String]
    /// Its helpers that only write through its writer: `select(_ destination:)` is `set(.destination(destination))`.
    var helpers: [Helper] = []

    func field(_ name: String) -> SwiftProperty? { fields.first { $0.name == name } }
    func helper(_ name: String) -> Helper? { helpers.first { $0.name == name } }
    var hasClear: Bool { kinds.contains { $0.name == "clear" } }
    /// Whether it says what is in flight and why work failed, as this family's services do.
    var hasStatus: Bool { field("loading") != nil && field("lastError") != nil }
    var isPersisted: Bool { persistKey != nil }
}
