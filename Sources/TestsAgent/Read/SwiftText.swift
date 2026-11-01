//  WHAT: Swift read by its shape, as this family's agents write it: a block's body by its braces, a function's
//        signature and body, the stored properties one level inside a type, a call's arguments.
//  PIN:  READ, NOT COMPILED. What is not found is said in a note by whoever asked, never guessed; strings and
//        comments are skipped so a brace in a literal never closes a block.

import Foundation

enum SwiftText {
    /// The first capture of every match of `pattern` in `text` (the whole match when it captures nothing).
    static func matches(_ pattern: String, in text: String) -> [String] {
        groups(pattern, in: text).compactMap { $0.count > 1 ? $0[1] : $0.first }
    }

    /// Every match of `pattern`: the whole match, then each capture ("" when a capture took no part).
    static func groups(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    /// The index just past the `}` that closes the `{` at `open`; nil when it never closes.
    static func close(_ text: String, from open: String.Index) -> String.Index? {
        var depth = 0
        var index = open
        while index < text.endIndex {
            let c = text[index]
            if c == "\"" {
                index = skipString(text, from: index)
                continue
            }
            if c == "/", text.index(after: index) < text.endIndex {
                let next = text[text.index(after: index)]
                if next == "/" {
                    index = text[index...].firstIndex(of: "\n") ?? text.endIndex
                    continue
                }
                if next == "*", let end = text.range(of: "*/", range: text.index(index, offsetBy: 2)..<text.endIndex) {
                    index = end.upperBound
                    continue
                }
            }
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return text.index(after: index) }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Past the string literal that opens at `start` (a `"`, a `"""`); a raw string's `#` before it is left alone,
    /// since its body holds no unescaped quote this family writes.
    private static func skipString(_ text: String, from start: String.Index) -> String.Index {
        let triple = text[start...].hasPrefix("\"\"\"")
        var index = text.index(start, offsetBy: triple ? 3 : 1)
        while index < text.endIndex {
            if text[index] == "\\" {
                index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if triple {
                if text[index...].hasPrefix("\"\"\"") { return text.index(index, offsetBy: 3) }
            } else if text[index] == "\"" {
                return text.index(after: index)
            } else if text[index] == "\n" {
                return index
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    /// The body (between the braces) of the first block whose opening line matches `pattern`.
    static func body(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text),
              let open = text[range.lowerBound...].firstIndex(of: "{"),
              let end = close(text, from: open) else { return nil }
        return String(text[text.index(after: open)..<text.index(before: end)])
    }

    /// The lines of `body` that stand at its own level: not inside a nested block, a string or a comment.
    static func topLevelLines(_ body: String) -> [String] {
        var lines: [String] = []
        var depth = 0
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if depth == 0, !trimmed.isEmpty, !trimmed.hasPrefix("//") { lines.append(trimmed) }
            depth += braceBalance(of: line)
            depth = max(0, depth)
        }
        return lines
    }

    /// Opening braces less closing ones on `line`, strings and comments left out.
    static func braceBalance(of line: String) -> Int {
        var balance = 0, quoted = false, escaped = false
        var previous: Character = " "
        for c in line {
            if quoted {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }
                continue
            }
            if c == "/" && previous == "/" { break }
            if c == "\"" { quoted = true } else if c == "{" { balance += 1 } else if c == "}" { balance -= 1 }
            previous = c
        }
        return balance
    }

    /// `text` cut at every `separator` outside brackets, parentheses, braces, angle brackets and quotes; pieces
    /// trimmed, empty ones dropped.
    static func split(_ text: String, on separator: Character) -> [String] {
        var pieces: [String] = [], current = "", depth = 0, quoted = false, escaped = false
        for c in text {
            if quoted {
                current.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }
                continue
            }
            switch c {
            case "\"": quoted = true; current.append(c)
            case "[", "(", "{", "<": depth += 1; current.append(c)
            case "]", ")", "}", ">": depth = max(0, depth - 1); current.append(c)
            case separator where depth == 0: pieces.append(current); current = ""
            default: current.append(c)
            }
        }
        pieces.append(current)
        return pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The text inside the parentheses that open at `open`, and the index past their close.
    static func parenthesized(_ text: String, from open: String.Index) -> (inside: String, end: String.Index)? {
        var depth = 0, quoted = false, escaped = false
        var index = open
        while index < text.endIndex {
            let c = text[index]
            if quoted {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }
            } else if c == "\"" {
                quoted = true
            } else if c == "(" || c == "[" {
                depth += 1
            } else if c == ")" || c == "]" {
                depth -= 1
                if depth == 0 { return (String(text[text.index(after: open)..<index]), text.index(after: index)) }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// The functions declared in `text`, each with its signature read and its body.
    static func functions(in text: String) -> [SwiftFunction] {
        let pattern = #"^[ \t]*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|static|nonisolated|mutating|override|final)\s+)*func\s+(`?\w+`?)\s*(?:<[^>]*>)?\s*\("#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        var found: [SwiftFunction] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let open = text.index(before: whole.upperBound)
            guard let (inside, afterParameters) = parenthesized(text, from: open),
                  let brace = text[afterParameters...].firstIndex(of: "{"),
                  let end = close(text, from: brace) else { continue }
            let between = text[afterParameters..<brace].trimmingCharacters(in: .whitespacesAndNewlines)
            var returns: String?
            if let arrow = between.range(of: "->") {
                let type = between[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                returns = type.components(separatedBy: " where ").first?.trimmingCharacters(in: .whitespaces)
            }
            let head = String(text[whole.lowerBound..<nameRange.lowerBound])
            let name = String(text[nameRange]).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            found.append(SwiftFunction(
                name: name,
                parameters: split(inside, on: ",").compactMap(SwiftParameter.init),
                returns: returns,
                isAsync: between.contains("async"),
                isThrowing: between.contains("throws"),
                isStatic: head.contains("static "),
                body: String(text[text.index(after: brace)..<text.index(before: end)]),
                attributes: head.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return found
    }

    /// The stored properties one level inside the block `pattern` opens: `var title: String = ""`, `let id: UUID`.
    static func storedProperties(of pattern: String, in text: String) -> [SwiftProperty] {
        guard let body = body(of: pattern, in: text) else { return [] }
        return topLevelLines(body).compactMap(SwiftProperty.init)
    }
}
