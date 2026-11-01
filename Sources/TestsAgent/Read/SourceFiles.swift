//  WHAT: The Swift files a call reads: the app's own (its services, pages and shared code) and each local package's
//        sources, walked by relative path so every answer keeps the host's spelling of the folder.

import Foundation

enum SourceFiles {
    /// Folders a walk of the app's code never enters: build products, version control, tests, packages, bundles.
    static let skippedInApp: Set<String> = [".build", ".git", ".swiftpm", "DerivedData", "node_modules", "Tests", "UITests", "Packages"]

    /// The Swift files under `root`, skipping `skipped` folders, dot folders, project bundles and asset catalogs.
    static func swift(under root: URL, skipping skipped: Set<String>) -> [SourceFile] {
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var found: [SourceFile] = []
        while let relative = walker.nextObject() as? String {
            let name = (relative as NSString).lastPathComponent
            if walker.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
                if skipped.contains(name) || name.hasPrefix(".") || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcassets") {
                    walker.skipDescendants()
                }
                continue
            }
            guard name.hasSuffix(".swift") else { continue }
            let url = root.appendingPathComponent(relative)
            if let text = try? String(contentsOf: url, encoding: .utf8) { found.append(SourceFile(url: url, text: text)) }
        }
        return found.sorted { $0.url.path < $1.url.path }
    }

    /// The modules `text` imports.
    static func imports(of text: String) -> [String] {
        SwiftText.matches(#"^\s*(?:@testable\s+|@_exported\s+)?import\s+(\w+)\s*$"#, in: text)
    }
}
