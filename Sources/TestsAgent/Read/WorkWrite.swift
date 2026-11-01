import Foundation

/// Where a piece of work's result goes.
enum WorkWrite: Sendable, Equatable {
    case none
    case replace(String)
    case append(String)

    var field: String? {
        switch self {
        case .none: return nil
        case .replace(let field), .append(let field): return field
        }
    }
}
