//  WHAT: The few lines of the app a test run needs: `RunMode` (a launch for a person, on mocks, or hosting the unit
//        tests), the root page left out while the app hosts its unit tests, each persisted service's store keyed
//        apart under tests and mocks, the iOS scheme running the UI tests, and the package imports a test file
//        forgot.
//  PIN:  NOTHING BUT THE TESTS DRIVES THE SERVICES. A hosted test run starts the app; its pages would load through
//        the live client and race the tests on the same services (seen: a page's refresh held a service's lane
//        while a test waited). Hosting its unit tests, the app shows no page.
//  PIN:  A TEST NEVER TOUCHES WHAT A PERSON SAVED. A persisted store's key gains `.tests` under a test run and `.mock`
//        on a mock launch, beside the person's, never in it.
//  PIN:  EVERY EDIT IS IDEMPOTENT. A second call finds each edit made and changes nothing.

import Foundation

enum AppEdits {
    static let runMode = #"""
    import Foundation

    /// How this launch of the app runs: for a person, on mock backend responses (`-mock YES` or `MOCK=1`), or as the
    /// host of its unit tests. A mock launch and a test run keep their stored state apart from the person's, and while
    /// the app hosts its unit tests it shows no pages, so nothing but the tests drives its services.
    enum RunMode: String, Sendable {
        case person
        case mock
        case tests

        /// This launch's mode, read once.
        static let current: RunMode = {
            let environment = ProcessInfo.processInfo.environment
            if environment["XCTestBundlePath"] != nil || environment["XCTestConfigurationFilePath"] != nil { return .tests }
            if UserDefaults.standard.bool(forKey: "mock") || environment["MOCK"] == "1" { return .mock }
            return .person
        }()

        /// What a persisted service's key ends with: nothing for a person, `.mock` or `.tests` otherwise.
        static var storeSuffix: String { current == .person ? "" : "." + current.rawValue }

        /// Whether the app shows its pages: not while it hosts its unit tests.
        static var showsPages: Bool { current != .tests }
    }

    """#

    /// Where `RunMode` goes: beside the app's other utilities, else beside its `App`.
    static func runModeFile(index: AppIndex) -> URL {
        let utility = index.project.root.appendingPathComponent("Shared/Utility")
        if FileManager.default.fileExists(atPath: utility.path) { return utility.appendingPathComponent("RunMode.swift") }
        if let app = appFile(index) { return app.url.deletingLastPathComponent().appendingPathComponent("RunMode.swift") }
        return index.project.root.appendingPathComponent("Shared/Utility/RunMode.swift")
    }

    /// The file with the app's `@main` `App`.
    static func appFile(_ index: AppIndex) -> SourceFile? {
        index.files.first { $0.text.contains("@main") && $0.text.range(of: #":\s*App\s*\{"#, options: .regularExpression) != nil }
    }

    /// The app's `WindowGroup` with its content shown only when `RunMode.showsPages`; nil when it already is, or the
    /// app has no `WindowGroup` this can read.
    static func guardedApp(_ text: String) -> String? {
        guard !text.contains("RunMode.showsPages"),
              let start = text.range(of: #"WindowGroup(\([^)]*\))?\s*\{"#, options: .regularExpression),
              let open = text[start].lastIndex(of: "{"),
              let end = SwiftText.close(text, from: open) else { return nil }
        let closing = text.index(before: end)
        let inside = String(text[text.index(after: open)..<closing])
        let lines = inside.components(separatedBy: "\n")
        let content = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !content.isEmpty else { return nil }
        let indent = String(content[0].prefix { $0 == " " })
        let wrapped = ["", "\(indent)if RunMode.showsPages {"] + content.map { "    " + $0 } + ["\(indent)}"]
        let closingIndent = String(String(text[text.startIndex..<closing]).split(separator: "\n", omittingEmptySubsequences: false).last?.prefix { $0 == " " } ?? "")
        return String(text[..<text.index(after: open)]) + wrapped.joined(separator: "\n") + "\n" + closingIndent + String(text[closing...])
    }

    /// A center's `@Store(persist: "key"` keyed apart under tests and mocks; nil when it already is or persists nothing.
    static func keyedStore(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(@Store\(\s*persist:\s*"[^"]+")(?!\s*\+\s*RunMode\.storeSuffix)"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard regex.firstMatch(in: text, range: range) != nil else { return nil }
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1 + RunMode.storeSuffix")
    }

    /// A scheme with its UI tests run (`skipped` false) or kept skipped; nil when they already are, or it has none.
    static func runningUITests(_ text: String, targets: [String], run: Bool = true) -> String? {
        let from = run ? "skipped = \"YES\"" : "skipped = \"NO\"", to = run ? "skipped = \"NO\"" : "skipped = \"YES\""
        guard let regex = try? NSRegularExpression(pattern: #"<TestableReference[\s\S]*?</TestableReference>"#) else { return nil }
        var result = text
        var changed = false
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let block = String(result[range])
            let name = SwiftText.matches(#"BlueprintName\s*=\s*"([^"]+)""#, in: block).first ?? ""
            guard targets.contains(name), block.contains(from) else { continue }
            result.replaceSubrange(range, with: block.replacingOccurrences(of: from, with: to))
            changed = true
        }
        return changed ? result : nil
    }

    /// A UI test that launches the app with no `-mock` launched on mock backend responses too; nil when every launch
    /// already is.
    static func launchingOnMocks(_ text: String) -> String? {
        guard text.contains("XCUIApplication()"), !text.contains("\"-mock\"") else { return nil }
        var changed = false
        let lines = text.components(separatedBy: "\n").flatMap { line -> [String] in
            guard let match = SwiftText.groups(#"^(\s*)(\w+)\.launch\(\)\s*$"#, in: line).first else { return [line] }
            changed = true
            return ["\(match[1])\(match[2]).launchArguments += [\"-mock\", \"YES\"]", line]
        }
        return changed ? lines.joined(separator: "\n") : nil
    }

    /// The test file with an `import` for each package module whose types it names and does not import; nil when it
    /// misses none.
    static func importingPackages(_ text: String, types: [String: String]) -> String? {
        let imported = Set(SourceFiles.imports(of: text))
        var missing: [String] = []
        let words = Set(SwiftText.matches(#"\b([A-Z]\w*)\b"#, in: text))
        for word in words.sorted() {
            guard let module = types[word], !imported.contains(module), !missing.contains(module) else { continue }
            missing.append(module)
        }
        guard !missing.isEmpty else { return nil }
        // After the last plain import, so `@testable import` stays last.
        var lines = text.components(separatedBy: "\n")
        guard let last = lines.lastIndex(where: { $0.range(of: #"^import \w+\s*$"#, options: .regularExpression) != nil }) else { return nil }
        lines.insert(contentsOf: missing.sorted().map { "import \($0)" }, at: last + 1)
        return lines.joined(separator: "\n")
    }
}
