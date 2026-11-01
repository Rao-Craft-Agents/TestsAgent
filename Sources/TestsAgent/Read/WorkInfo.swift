import Foundation

/// One piece of a service's work: its entry, its reducer, what it awaits and what it writes.
struct WorkInfo: Sendable {
    /// The center's event and the entry's name: `load`.
    var verb: String
    /// The reducer: `Load`.
    var typeName: String
    /// The ticketed entry a caller awaits.
    var entry: SwiftFunction
    /// What `loading` reads while it is in flight.
    var loadingKey: String?
    var write: WorkWrite
    /// The effect's text and the work function's, where the calls it awaits are read.
    var text: String
    /// The `set` calls it makes beside its result's and its status's.
    var sets: [SetCall]
    /// The effect's names for the payload's fields: `isFirstLaunch` for `meta.isFirstLaunch`.
    var payloadNames: [String: String]
}
