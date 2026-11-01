//  WHAT: Everything a call reads of the app at once: its project, its code and its packages' code, its services and
//        their work, its pages, its destinations, its clients, and the seams the work sends through.

import Foundation

struct AppIndex: Sendable {
    let project: AppProject
    /// The app's own Swift files.
    let files: [SourceFile]
    /// The local packages' Swift files.
    let packageFiles: [SourceFile]
    let services: [ServiceInfo]
    let pages: [PageInfo]
    let destinations: Destinations?
    let clients: [ClientInfo]
    /// What each piece of work sends through, by `Service.verb`.
    let reaches: [String: WorkReach]
    /// Types with a `preview`, from the app and its packages.
    let previews: Set<String>
    /// Enums the app and its packages declare, with their cases.
    let enums: [String: [String]]

    init(project: AppProject) {
        self.project = project
        files = SourceFiles.swift(under: project.root, skipping: SourceFiles.skippedInApp)
        let packages = AppProject.contents(of: project.root.appendingPathComponent("Packages"))
        packageFiles = packages.flatMap { SourceFiles.swift(under: $0.appendingPathComponent("Sources"), skipping: [".build"]) }
        services = ServiceReader.services(in: files)
        pages = PageReader.pages(in: files)
        destinations = Destinations.read(in: files)
        clients = ClientReader.clients(in: project.root)
        var previews: Set<String> = [], enums: [String: [String]] = [:]
        for file in files + packageFiles {
            for name in SwiftText.matches(#"static (?:let|var) preview: (\w+)"#, in: file.text) { previews.insert(name) }
            for name in SwiftText.matches(#"^\s*(?:public\s+)?enum\s+(\w+)\b[^{]*\{"#, in: file.text) where enums[name] == nil {
                if let body = SwiftText.body(of: #"^\s*(?:public\s+)?enum\s+\#(name)\b"#, in: file.text) { enums[name] = ClientReader.cases(in: body) }
            }
        }
        self.previews = previews
        self.enums = enums
        var reaches: [String: WorkReach] = [:]
        let everything = files + packageFiles
        for service in services {
            for work in service.works {
                reaches["\(service.name).\(work.verb)"] = WorkReach.read(work, clients: clients, files: everything)
            }
        }
        self.reaches = reaches
    }

    func reach(_ service: ServiceInfo, _ work: WorkInfo) -> WorkReach { reaches["\(service.name).\(work.verb)"] ?? WorkReach() }

    func service(named name: String) -> ServiceInfo? { services.first { $0.name == name } }

    func client(_ name: String) -> ClientInfo? { clients.first { $0.client == name } }

    /// Every seam any work sends through, each once.
    var seams: [Seam] {
        var seen: [Seam] = []
        for reach in reaches.keys.sorted().compactMap({ reaches[$0] }) {
            for call in reach.calls where !seen.contains(call.seam) { seen.append(call.seam) }
        }
        return seen
    }

    /// The clients the seams hold, each once, in the order of their seams.
    var mockedClients: [ClientInfo] {
        var names: [String] = []
        for seam in seams where seam.isAssignable && !names.contains(seam.client) { names.append(seam.client) }
        return names.compactMap(client)
    }

    /// The service a page's relay reads.
    func service(of relay: PageInfo.Relay) -> ServiceInfo? { service(named: relay.service) }
}
