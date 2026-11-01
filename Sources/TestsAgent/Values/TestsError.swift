import Foundation

/// What a call can say instead of writing.
public enum TestsError: Error, Equatable, CustomStringConvertible {
    /// Everything the call cannot honour, each in a sentence, so all are fixed in one call. Nothing was written.
    case refused([String])

    public var description: String {
        switch self {
        case .refused(let reasons):
            let count = reasons.count == 1 ? "1 problem" : "\(reasons.count) problems"
            return "\(count), so nothing was written:\n" + reasons.map { "- \($0)" }.joined(separator: "\n")
        }
    }
}
