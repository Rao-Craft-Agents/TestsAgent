import Foundation

/// What `mocks` wrote beside a client: `static func mock(_ scenario: MockScenario, latency: Duration) -> Client`.
struct MockSupport: Sendable {
    /// The scenario type's cases.
    var scenarios: [String]
    /// Whether `mock` takes a `latency:`.
    var takesLatency: Bool
}
