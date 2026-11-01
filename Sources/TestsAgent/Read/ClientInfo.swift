//  WHAT: A typed API client the app links, as `network` writes one into `Packages/<Kit>`: its client type, the
//        coding it writes JSON with, its base URL, each endpoint's method, path, answer and paging, the types the
//        endpoints answer (their fields, their previews), and the mock `mocks` adds beside it.
//  PIN:  READ OFF THE PACKAGE'S OWN SWIFT. `api.json` says the package is `network`'s; the endpoints and types are
//        read from the Swift it wrote, which is what the app compiles against.

import Foundation

struct ClientInfo: Sendable {
    /// The package's module: `RecipeKit`.
    var module: String
    var folder: URL
    /// The client type: `RecipeClient`.
    var client: String
    /// The type whose `encoder()` writes JSON as the API does: `RecipeCoding`.
    var coding: String?
    var baseURL: String?
    var endpoints: [EndpointInfo]
    /// The types the package declares, by name.
    var types: [String: ModelType]
    /// `mocks`'s `.mock(_:latency:)` and the scenarios it answers, when the package has them.
    var mock: MockSupport?

    func endpoint(_ name: String) -> EndpointInfo? { endpoints.first { $0.name == name } }
}
