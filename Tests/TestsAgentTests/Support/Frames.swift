import Foundation

/// The frames a run yields, kept from whatever task yields them.
final class Frames: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String] = []
    func add(_ frame: String) { lock.withLock { kept.append(frame) } }
    var all: [String] { lock.withLock { kept } }
}
