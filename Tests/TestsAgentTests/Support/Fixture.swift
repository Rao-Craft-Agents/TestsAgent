import Foundation

enum Fixture {
    /// A folder of its own for one test, removed with the process's temporary files.
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tests-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The Supper app (`AppFixture`) written into a folder of its own, `change` applied to each file first.
    static func app(_ change: (String, String) -> String = { _, text in text }) throws -> URL {
        let root = try folder()
        for (path, text) in AppFixture.files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(change(path, text + "\n").utf8).write(to: url)
        }
        return root
    }

    /// The text of `path` under `root`.
    static func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
