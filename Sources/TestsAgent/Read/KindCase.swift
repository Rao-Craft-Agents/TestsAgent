import Foundation

/// A case of a writer's `Kind`: `recipes([Recipe])`, `booted(isFirstLaunch: Bool, at: Date)`, `clear`.
struct KindCase: Sendable, Equatable {
    var name: String
    var payload: String?
}
