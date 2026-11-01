import Foundation

/// One endpoint: a method of the client.
struct EndpointInfo: Sendable {
    var name: String
    /// `GET`, `POST`.
    var method: String
    /// The path, a `{name}` for each parameter: `/v1/recipes/{id}`.
    var path: String
    /// What it answers: `[Recipe]`, `RecipePage`; nil for nothing.
    var response: String?
    var parameters: [SwiftParameter]
    /// The query item a page number goes in, when the endpoint is paged by page.
    var pageQuery: String?
    /// Whether the endpoint has a `…Pages` sequence.
    var isPaged: Bool
}
