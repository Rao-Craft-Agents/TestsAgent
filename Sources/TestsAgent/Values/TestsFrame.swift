import Foundation

/// What a run says as it goes.
public enum TestsFrame: Sendable {
    /// The project was read: its services with work, its pages and its destinations.
    case read(services: Int, pages: Int, destinations: Int)
    /// The host's model said what a page action should leave: which page and action, in how many rounds.
    case asked(page: String, action: String, rounds: Int)
    /// The files are written.
    case written(TestsResult)

    public var result: TestsResult? {
        if case .written(let result) = self { return result }
        return nil
    }
}
