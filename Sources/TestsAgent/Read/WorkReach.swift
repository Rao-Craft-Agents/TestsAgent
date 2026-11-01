import Foundation

/// What a piece of work reaches beyond its service: the endpoints it calls through seams, and anything that would
/// reach a live server a test cannot stand in front of.
struct WorkReach: Sendable {
    var calls: [EndpointCall] = []
    /// Endpoint calls through something that is not a seam a test can assign.
    var unread: [String] = []
    /// Why the work would reach a live server, when it would.
    var live: String?

    var isMocked: Bool { !calls.isEmpty && unread.isEmpty && live == nil && calls.allSatisfy(\.seam.isAssignable) }

    static func read(_ work: WorkInfo, clients: [ClientInfo], files: [SourceFile]) -> WorkReach {
        let (calls, unread) = SeamReader.calls(in: work.text, clients: clients, files: files)
        var reach = WorkReach(calls: calls, unread: unread)
        if work.text.contains("URLSession") || work.text.range(of: #""https?://"#, options: .regularExpression) != nil {
            reach.live = "it sends with URLSession or names a URL itself"
        }
        return reach
    }
}
