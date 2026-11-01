//  WHAT: The app's pages, each `GraniteComponent` read with its folder: its relays, what it is made with, its
//        title and the actions its `+Actions` file declares.

import Foundation

enum PageReader {
    static func pages(in files: [SourceFile]) -> [PageInfo] {
        var found: [PageInfo] = []
        for file in files {
            for name in SwiftText.matches(#"^\s*(?:public\s+)?struct\s+(\w+)\s*:\s*[^{]*\bGraniteComponent\b"#, in: file.text) {
                let folder = file.url.deletingLastPathComponent()
                let own = files.filter { $0.url.deletingLastPathComponent().path == folder.path || $0.url.path.hasPrefix(folder.path + "/Views/") }
                found.append(read(name, declaration: file.text, folder: folder, files: own))
            }
        }
        return found.sorted { $0.name < $1.name }
    }

    static func read(_ name: String, declaration: String, folder: URL, files: [SourceFile]) -> PageInfo {
        let body = SwiftText.body(of: #"^\s*(?:public\s+)?struct\s+\#(name)\s*:"#, in: declaration) ?? ""
        let relays = SwiftText.groups(#"@Relay(?:\([^)]*\))?\s+(?:private\s+|public\s+)?var\s+(\w+)\s*:\s*(\w+)"#, in: body)
            .map { PageInfo.Relay(name: $0[1], service: $0[2]) }
        var inputs: [SwiftParameter] = []
        if let initializer = SwiftText.functions(in: body).first(where: { $0.name == "init" }) {
            inputs = initializer.parameters
        } else if let found = SwiftText.groups(#"^\s*init\s*\(([^)]*)\)"#, in: body).first {
            inputs = SwiftText.split(found[1], on: ",").compactMap(SwiftParameter.init)
        } else {
            inputs = SwiftText.topLevelLines(body).filter { $0.hasPrefix("let ") }.compactMap(SwiftProperty.init)
                .filter { $0.defaultValue == nil }
                .compactMap { property in property.type.map { SwiftParameter(label: property.name, name: property.name, type: $0) } }
        }
        var actions: [ActionInfo] = []
        var title: String?
        var imports: [String] = []
        for file in files where file.url.lastPathComponent.hasPrefix(name) || file.url.path.contains("/Views/") {
            imports += SourceFiles.imports(of: file.text)
            if file.url.lastPathComponent == "\(name)+Actions.swift" {
                actions = SwiftText.functions(in: file.text).filter { !$0.isStatic && !$0.attributes.contains("private") }.map { function in
                    ActionInfo(name: function.name, parameters: function.parameters,
                               statements: SwiftText.topLevelLines(function.body), isAsync: function.isAsync, isThrowing: function.isThrowing)
                }
            }
            if file.url.lastPathComponent == "\(name)+View.swift" || file.url.lastPathComponent == "\(name).swift" {
                title = title ?? SwiftText.matches(#"\.navigationTitle\(\s*"((?:[^"\\]|\\.)*)"\s*\)"#, in: file.text).first
            }
        }
        return PageInfo(name: name, folder: folder, relays: relays, inputs: inputs, actions: actions, title: title,
                        imports: Array(Set(imports).subtracting(ServiceReader.standardModules)).sorted())
    }
}
