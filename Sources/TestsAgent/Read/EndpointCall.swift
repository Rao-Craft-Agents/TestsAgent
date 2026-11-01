import Foundation

/// A call a piece of work makes to an endpoint: through which seam, of which client.
struct EndpointCall: Sendable, Equatable {
    var seam: Seam
    var endpoint: String
}
