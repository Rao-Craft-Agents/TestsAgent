import Foundation

/// What a mock backend answers during a test: the states an app's services are proved in.
public enum TestsScenario: String, Codable, Sendable, CaseIterable {
    /// Two pages of items, then an empty page; every other endpoint its sample.
    case normal
    /// Every list empty.
    case empty
    /// Every request a server error: the failure is recorded, and a try again clears it.
    case failing
    /// As normal, a moment late, so work is seen in flight.
    case slow
}
