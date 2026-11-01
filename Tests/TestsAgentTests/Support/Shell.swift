import Foundation

/// A command run to its end, its output kept in a file beside the work (a build says more than a pipe holds).
enum Shell {
    struct Run {
        let status: Int32
        let log: String

        /// The log's last `count` lines: what a failure message shows.
        func tail(_ count: Int = 40) -> String { log.split(separator: "\n").suffix(count).joined(separator: "\n") }
    }

    static func run(_ tool: String, _ arguments: [String], in folder: URL, log: URL, input: String? = nil) throws -> Run {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        process.currentDirectoryURL = folder
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        process.standardOutput = output
        process.standardError = output
        let feed = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : feed
        try process.run()
        if let input {
            feed.fileHandleForWriting.write(Data(input.utf8))
            try feed.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        try output.close()
        return Run(status: process.terminationStatus, log: (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }
}
