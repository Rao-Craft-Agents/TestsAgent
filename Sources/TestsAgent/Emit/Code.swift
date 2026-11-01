//  WHAT: Swift written a line at a time, each at the depth of the blocks it is in.

import Foundation

struct Code {
    private(set) var lines: [String] = []
    private var depth = 0

    /// A line at the current depth; an empty one stays empty.
    mutating func line(_ text: String = "") {
        lines.append(text.isEmpty ? "" : String(repeating: "    ", count: depth) + text)
    }

    /// Several lines, each at the current depth.
    mutating func lines(_ texts: [String]) { texts.forEach { line($0) } }

    /// `text` as a doc comment, wrapped at 120 columns.
    mutating func doc(_ text: String) {
        let width = 116 - depth * 4
        var current = ""
        for word in text.split(separator: " ") {
            if !current.isEmpty, current.count + 1 + word.count > width {
                line("/// " + current)
                current = String(word)
            } else {
                current += (current.isEmpty ? "" : " ") + word
            }
        }
        if !current.isEmpty { line("/// " + current) }
    }

    /// A line that opens a block: what follows is one level in.
    mutating func open(_ text: String) {
        line(text)
        depth += 1
    }

    /// The block's end, back one level.
    mutating func close(_ text: String = "}") {
        depth = max(0, depth - 1)
        line(text)
    }

    /// A line that closes one block and opens the next: `} else {`.
    mutating func middle(_ text: String) {
        depth = max(0, depth - 1)
        line(text)
        depth += 1
    }

    var text: String { lines.joined(separator: "\n") + "\n" }
}
