//  WHAT: The app's destinations at once: each case of `AppDestination` with its title and page, and whether a
//        launch opens the one `-destination <case>` names.

import Foundation

struct Destinations: Sendable {
    var cases: [DestinationInfo]
    /// Whether a launch opens the one `-destination <case>` names.
    var opensFromLaunch: Bool

    static func read(in files: [SourceFile]) -> Destinations? {
        for file in files {
            guard let body = SwiftText.body(of: #"^\s*(?:public\s+)?enum\s+AppDestination\b"#, in: file.text) else { continue }
            let names = ClientReader.cases(in: body)
            var titles: [String: String] = [:], pages: [String: String] = [:]
            if let titleBody = SwiftText.body(of: #"var\s+title\s*:\s*String"#, in: body) {
                for match in SwiftText.groups(#"case\s+\.(\w+)\s*:\s*(?:return\s+)?(?:String\(localized:\s*)?"((?:[^"\\]|\\.)*)""#, in: titleBody) {
                    titles[match[1]] = match[2]
                }
            }
            if let viewBody = SwiftText.body(of: #"var\s+view\s*:\s*some\s+View"#, in: body) {
                for match in SwiftText.groups(#"case\s+\.(\w+)\s*:\s*(?:return\s+)?(?:AnyView\()?([A-Z]\w*)\s*\("#, in: viewBody) {
                    pages[match[1]] = match[2]
                }
            }
            let opens = body.contains("forKey: \"destination\"")
            return Destinations(cases: names.map { DestinationInfo(name: $0, title: titles[$0], page: pages[$0]) }, opensFromLaunch: opens)
        }
        return nil
    }
}
