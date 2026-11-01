import Foundation

/// What a call answers: the files written or edited, as absolute paths, and what they prove.
public struct TestsResult: Codable, Sendable, Equatable {
    /// The first file written.
    public var path: String?
    /// Every file written or edited: the tests, their support, the scheme and the app's run mode.
    public var paths: [String]
    /// The services whose work is tested.
    public var services: [String]
    /// The pages drawn and driven.
    public var pages: [String]
    /// The destinations a launch test opens.
    public var destinations: [String]
    /// How many tests were written.
    public var tests: Int
    /// One sentence each: what the call decided, left out, or found the app missing.
    public var notes: [String]

    public init(path: String?, paths: [String], services: [String], pages: [String], destinations: [String], tests: Int, notes: [String]) {
        self.path = path; self.paths = paths; self.services = services; self.pages = pages
        self.destinations = destinations; self.tests = tests; self.notes = notes
    }
}
