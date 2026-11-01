//  WHAT: The app a call tests: its folder, its Xcode project, the module its code compiles into, the folders its
//        unit tests and UI tests are synchronized from, and its shared schemes.
//  PIN:  THE PROJECT FILE IS READ BY `plutil`. An old-style plist is Apple's to parse; what this needs of it (the
//        targets, their settings, their synchronized folders) is read off the JSON plutil makes of it.

import Foundation

struct AppProject: Sendable {
    /// The app's folder: the host's, or the one folder below it that holds a project.
    let root: URL
    let project: URL
    /// The app's name, as its project is named.
    let name: String
    /// The module the app's code compiles into: what its tests `@testable import`.
    let module: String
    /// The folder its unit tests are synchronized from; nil when it has no unit-test target.
    let unitTests: URL?
    /// The folder its UI tests are synchronized from; nil when it has no UI-test target.
    let uiTests: URL?
    /// The UI-test targets, by name.
    let uiTestTargets: [String]
    /// The shared schemes.
    let schemes: [URL]

    /// The app's project under `folder` (the folder itself, or the one folder below it that holds one); nil when
    /// there is none to read.
    static func find(in folder: URL) -> AppProject? {
        if let project = Self.project(in: folder) { return read(project, root: folder) }
        let below = Self.contents(of: folder).filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { child in Self.project(in: child).map { (child, $0) } }
        guard below.count == 1 else { return nil }
        return read(below[0].1, root: below[0].0)
    }

    static func project(in folder: URL) -> URL? {
        let found = contents(of: folder).filter { $0.pathExtension == "xcodeproj" }
        return found.count == 1 ? found[0] : nil
    }

    static func contents(of folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().map { folder.appendingPathComponent($0) }
    }

    private static func read(_ project: URL, root: URL) -> AppProject? {
        let name = project.deletingPathExtension().lastPathComponent
        let objects = Self.objects(of: project.appendingPathComponent("project.pbxproj")) ?? [:]
        let targets = objects.values.filter { $0["isa"] as? String == "PBXNativeTarget" }
        func settings(_ target: [String: Any]) -> [String: Any] {
            guard let list = target["buildConfigurationList"] as? String,
                  let configurations = objects[list]?["buildConfigurations"] as? [String] else { return [:] }
            let all = configurations.compactMap { objects[$0] }
            let chosen = all.first { $0["name"] as? String == "Debug" } ?? all.first
            return chosen?["buildSettings"] as? [String: Any] ?? [:]
        }
        func folders(_ target: [String: Any]) -> [URL] {
            ((target["fileSystemSynchronizedGroups"] as? [String]) ?? []).compactMap { objects[$0]?["path"] as? String }
                .map { root.appendingPathComponent($0) }
        }
        let apps = targets.filter { ($0["productType"] as? String)?.hasSuffix(".application") == true }
            .sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        var module = Self.identifier(name)
        if let app = apps.first {
            let values = settings(app)
            let targetName = app["name"] as? String ?? name
            let product = (values["PRODUCT_MODULE_NAME"] as? String) ?? (values["PRODUCT_NAME"] as? String) ?? targetName
            module = Self.identifier(product.replacingOccurrences(of: "$(TARGET_NAME)", with: targetName))
        }
        let units = targets.filter { ($0["productType"] as? String)?.hasSuffix(".unit-test") == true }
        let uis = targets.filter { ($0["productType"] as? String)?.hasSuffix(".ui-testing") == true }
        let schemes = Self.contents(of: project.appendingPathComponent("xcshareddata/xcschemes")).filter { $0.pathExtension == "xcscheme" }
        return AppProject(root: root, project: project, name: name, module: module,
                          unitTests: units.lazy.flatMap(folders).first, uiTests: uis.lazy.flatMap(folders).first,
                          uiTestTargets: uis.compactMap { $0["name"] as? String }.sorted(), schemes: schemes)
    }

    /// A product name as Swift spells its module: anything but letters, digits and `_` made `_`.
    static func identifier(_ name: String) -> String {
        var text = String(name.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
        if text.first?.isNumber == true { text = "_" + text }
        return text
    }

    /// The project file's objects, by id, as plutil reads them; nil when it cannot.
    static func objects(of pbxproj: URL) -> [String: [String: Any]]? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/plutil") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = ["-convert", "json", "-o", "-", pbxproj.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["objects"] as? [String: [String: Any]]
    }

    /// The scheme named `name`, when the project shares it.
    func scheme(_ name: String) -> URL? { schemes.first { $0.deletingPathExtension().lastPathComponent == name } }
}
