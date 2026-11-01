import Foundation

/// A type a package declares: its stored fields and whether it has a `preview`.
struct ModelType: Sendable {
    var name: String
    var isEnum: Bool
    var fields: [SwiftProperty]
    var cases: [String]
    var hasPreview: Bool

    /// The `id` field's type, when it has one a test can set.
    var idType: String? {
        guard let id = fields.first(where: { $0.name == "id" }), !id.isLet else { return nil }
        return id.type
    }
}
