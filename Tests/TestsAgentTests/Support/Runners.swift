import Foundation

/// The family's agents as Craft calls them: the runner installed on this Mac, one JSON line in, from inside the app's
/// folder, the call's `directory` set.
enum Runners {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// The `output` of one call to the installed `name` runner (`GraniteAgent`) with `word` and `input`.
    @discardableResult
    static func call(_ name: String, _ word: String, _ input: [String: Any], in app: URL, log: URL) throws -> [String: Any] {
        let runner = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".rao/apps/craft/agents/\(name)/agent")
        guard FileManager.default.isExecutableFile(atPath: runner.path) else { throw Failure(description: "\(name) is not installed at \(runner.path)") }
        let call: [String: Any] = ["perform": ["word": word, "directory": app.path, "ask": "make the fixture app", "model": false, "input": input]]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: call), as: UTF8.self) + "\n"
        let run = try Shell.run(runner.path, [], in: app, log: log, input: line)
        for text in run.log.split(separator: "\n") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { continue }
            if let output = object["output"] as? [String: Any] { return output }
            if let failed = object["failed"] { throw Failure(description: "\(word) failed: \(failed)") }
        }
        throw Failure(description: "\(word) answered nothing: \(run.tail())")
    }
}
