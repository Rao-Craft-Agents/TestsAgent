//  WHAT: An app as granite and network make it (a recipe app, Supper): its project, root, services, pages,
//        destinations and client package, trimmed to what the tests agent reads, written into a folder of a test's own.

import Foundation

enum AppFixture {
    /// The app's files, by their path inside its folder.
    static let files: [String: String] = [
        "Supper.xcodeproj/project.pbxproj": ##"""
        // !$*UTF8*$!
        {
        	archiveVersion = 1;
        	classes = {
        	};
        	objectVersion = 77;
        	objects = {
        		0A11CE0000000000000000A1 /* Supper */ = {
        			isa = PBXProject;
        			mainGroup = 0A11CE0000000000000000B1;
        			targets = (
        				0A11CE0000000000000000C1 /* Supper-iOS */,
        				0A11CE0000000000000000C2 /* Supper-macOS */,
        				0A11CE0000000000000000C3 /* SupperTests-macOS */,
        				0A11CE0000000000000000C4 /* SupperUITests-iOS */,
        				0A11CE0000000000000000C5 /* SupperUITests-macOS */,
        			);
        		};
        		0A11CE0000000000000000B1 = {
        			isa = PBXGroup;
        			children = (
        				0A11CE0000000000000000D1 /* Shared */,
        				0A11CE0000000000000000D2 /* Tests */,
        				0A11CE0000000000000000D3 /* UITests */,
        			);
        			sourceTree = "<group>";
        		};
        		0A11CE0000000000000000D1 /* Shared */ = {isa = PBXFileSystemSynchronizedRootGroup; path = Shared; sourceTree = "<group>"; };
        		0A11CE0000000000000000D2 /* Tests */ = {isa = PBXFileSystemSynchronizedRootGroup; path = Tests; sourceTree = "<group>"; };
        		0A11CE0000000000000000D3 /* UITests */ = {isa = PBXFileSystemSynchronizedRootGroup; path = UITests; sourceTree = "<group>"; };
        		0A11CE0000000000000000C1 /* Supper-iOS */ = {
        			isa = PBXNativeTarget;
        			buildConfigurationList = 0A11CE0000000000000000E1;
        			fileSystemSynchronizedGroups = (0A11CE0000000000000000D1);
        			name = "Supper-iOS";
        			productName = Supper;
        			productType = "com.apple.product-type.application";
        		};
        		0A11CE0000000000000000C2 /* Supper-macOS */ = {
        			isa = PBXNativeTarget;
        			buildConfigurationList = 0A11CE0000000000000000E1;
        			fileSystemSynchronizedGroups = (0A11CE0000000000000000D1);
        			name = "Supper-macOS";
        			productName = Supper;
        			productType = "com.apple.product-type.application";
        		};
        		0A11CE0000000000000000C3 /* SupperTests-macOS */ = {
        			isa = PBXNativeTarget;
        			buildConfigurationList = 0A11CE0000000000000000E2;
        			fileSystemSynchronizedGroups = (0A11CE0000000000000000D2);
        			name = "SupperTests-macOS";
        			productName = SupperTests;
        			productType = "com.apple.product-type.bundle.unit-test";
        		};
        		0A11CE0000000000000000C4 /* SupperUITests-iOS */ = {
        			isa = PBXNativeTarget;
        			buildConfigurationList = 0A11CE0000000000000000E2;
        			fileSystemSynchronizedGroups = (0A11CE0000000000000000D3);
        			name = "SupperUITests-iOS";
        			productName = SupperUITests;
        			productType = "com.apple.product-type.bundle.ui-testing";
        		};
        		0A11CE0000000000000000C5 /* SupperUITests-macOS */ = {
        			isa = PBXNativeTarget;
        			buildConfigurationList = 0A11CE0000000000000000E2;
        			fileSystemSynchronizedGroups = (0A11CE0000000000000000D3);
        			name = "SupperUITests-macOS";
        			productName = SupperUITests;
        			productType = "com.apple.product-type.bundle.ui-testing";
        		};
        		0A11CE0000000000000000E1 = {isa = XCConfigurationList; buildConfigurations = (0A11CE0000000000000000F1); };
        		0A11CE0000000000000000E2 = {isa = XCConfigurationList; buildConfigurations = (0A11CE0000000000000000F2); };
        		0A11CE0000000000000000F1 /* Debug */ = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.supper; PRODUCT_NAME = Supper; SWIFT_VERSION = 5.0; }; name = Debug; };
        		0A11CE0000000000000000F2 /* Debug */ = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; SWIFT_VERSION = 5.0; }; name = Debug; };
        	};
        	rootObject = 0A11CE0000000000000000A1 /* Project object */;
        }
        """##,
        "Shared/App.swift": ##"""
        import Granite
        import SwiftUI

        @main
        struct SupperApp: App {
            #if os(iOS)
            @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
            #elseif os(macOS)
            @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
            #endif

            init() {
                // Granite logs each store's restore at debug level; the app keeps its errors only.
                GraniteLogger.currentLevel = .error
            }

            var body: some Scene {
                WindowGroup {
                    Home()
                }
                #if os(macOS)
                .commands { AppCommands() }
                #endif
            }
        }
        """##,
        "Shared/Utility/AppRoot.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents

        /// The app's root: one relay to every service, held for the life of the process. Boot and long-running work
        /// start here, and AppKit, menus and the delegate reach the services through it.
        @MainActor
        final class AppRoot {
            static let shared = AppRoot()

            @Relay(.silence) var environment: EnvironmentService
            @Relay(.silence) var config: ConfigService
            @Relay(.silence) var recipes: RecipesService
            @Relay(.silence) var cooks: CooksService
            @Relay(.silence) var layout: LayoutService

            private init() {}

            /// Boots the app once its settings have loaded: counts the launch, then marks the environment ready. A boot
            /// that failed may run again; one that is ready does nothing.
            func boot() async {
                let phase = environment.state.phase
                guard phase != .ready else { return }
                // Read before the launch is counted: the settings' writer commits in the turn it is sent.
                let isFirstLaunch = config.state.launches == 0
                if phase == .idle { config.set(.launched(Date())) }
                do {
                    try await environment.boot(isFirstLaunch: isFirstLaunch)

                } catch {
                    environment.set(.failed(error.localizedDescription))
                }
            }
        }
        """##,
        "Shared/Utility/AppDestination.swift": ##"""
        import SwiftUI

        /// The places the app goes: what its tab bar and its sidebar list, each with its title, its symbol and its page.
        enum AppDestination: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
            case recipes
            case cooks
            case settings

            var id: Self { self }

            /// The destination a launch asks for with `-destination <name>`: how UI tests and screenshots open a page.
            static var launchArgument: AppDestination? {
                UserDefaults.standard.string(forKey: "destination").flatMap(AppDestination.init(rawValue:))
            }

            /// The destination's name, as the tab bar and the sidebar show it.
            var title: String {
                switch self {
                case .recipes: String(localized: "Recipes")
                case .cooks: String(localized: "Cooks")
                case .settings: String(localized: "Settings")
                }
            }

            /// The SF Symbol beside its name.
            var symbol: String {
                switch self {
                case .recipes: "book"
                case .cooks: "person.2"
                case .settings: "gearshape"
                }
            }

            /// The page it shows.
            @MainActor @ViewBuilder
            var view: some View {
                switch self {
                case .recipes: RecipeList()
                case .cooks: CookList()
                case .settings: Settings()
                }
            }
        }
        """##,
        "Services/RecipesService/RecipesService.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents
        import SwiftUI
        import RecipeKit

        /// The recipes people shared, newest first, kept between launches.
        struct RecipesService: GraniteService {
            @Service(.online) var center: Center

            init() {}

            /// What the service's work answers whoever asked for it.
            enum Reply: Sendable {
                case recipes([Recipe])
                case done
            }

            static let tickets = GraniteTickets<Reply>()

            /// The work that writes the state runs one call at a time, in the order it was asked for.
            static let lane = GraniteLane()
        }

        extension RecipesService: @unchecked Sendable {}

        extension RecipesService {
            /// Changes the state through its one writer, on main.
            func set(_ kind: Set.Meta.Kind) {
                let service = self
                onMain { service.center.set.send(Set.Meta(kind: kind)) }
            }

            /// A binding to a field of the state, written through `set`: `recipes.binding(\.recipes) { .recipes($0) }`.
            func binding<Value>(_ keyPath: KeyPath<Center.State, Value>, _ kind: @escaping (Value) -> Set.Meta.Kind) -> Binding<Value> {
                Binding(get: { self.state[keyPath: keyPath] }, set: { self.set(kind($0)) })
            }

            /// Loads a page of recipes, newest first.
            @discardableResult
            func load(page: Int) async throws -> [Recipe] {
                let ticket = await RecipesService.tickets.open()
                let service = self
                onMain { service.center.load.send(Load.Meta(ticket: ticket.id, page: page)) }
                guard case .recipes(let value) = try await RecipesService.tickets.wait(ticket.id) else {
                    throw TicketError.refused("load answered with something else")
                }
                return value
            }

            /// Adds the next page.
            @discardableResult
            func more(page: Int) async throws -> [Recipe] {
                let ticket = await RecipesService.tickets.open()
                let service = self
                onMain { service.center.more.send(More.Meta(ticket: ticket.id, page: page)) }
                guard case .recipes(let value) = try await RecipesService.tickets.wait(ticket.id) else {
                    throw TicketError.refused("more answered with something else")
                }
                return value
            }

            /// Marks a recipe as a favorite.
            func favor(id: Int) async throws {
                let ticket = await RecipesService.tickets.open()
                let service = self
                onMain { service.center.favor.send(Favor.Meta(ticket: ticket.id, id: id)) }
                _ = try await RecipesService.tickets.wait(ticket.id)
            }
        }
        """##,
        "Services/RecipesService/RecipesService+Center.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents
        import RecipeKit

        extension RecipesService {
            struct Center: GraniteCenter {
                struct State: GraniteState {
                    var recipes: [Recipe] = []
                    /// What is in flight, by the name of the work; nil when nothing is.
                    var loading: String?
                    /// Why the last work failed; nil once work starts again.
                    var lastError: String?

                    init() {}

                    enum CodingKeys: String, CodingKey {
                        case recipes
                    }

                    /// A field missing from the stored file, or stored as another type, reads as its default, so the
                    /// state keeps reading after a field is added; what is in flight is never stored.
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        recipes = (try? container.decodeIfPresent([Recipe].self, forKey: .recipes)) ?? []
                    }
                }

                @Event var set: Set.Reducer
                @Event var load: Load.Reducer
                @Event var more: More.Reducer
                @Event var favor: Favor.Reducer

                @Store(persist: "persistence.Supper.recipes.0001", autoSave: true, preload: true) var state: State

                init() {}
            }
        }
        """##,
        "Services/RecipesService/Reducers/RecipesService.Set.swift": ##"""
        import Foundation
        import Granite
        import RecipeKit

        extension RecipesService {
            /// The state's one writer: every change is a kind, applied on main by `RecipesOps.apply`.
            struct Set: GraniteReducer {
                typealias Center = RecipesService.Center
                init() {}

                struct Meta: GranitePayload {
                    enum Kind: Sendable {
                        case recipes([Recipe])
                        case appendRecipes([Recipe])
                        case loading(String?)
                        case failed(String)
                        case clear
                    }

                    var kind: Kind

                    init(kind: Kind) { self.kind = kind }
                }

                @Payload var meta: Meta?

                func reduce(state: inout Center.State) {
                    guard let meta else { return }
                    RecipesOps.apply(meta.kind, to: &state)
                }

                var thread: DispatchQueue? { .main }
            }
        }
        """##,
        "Services/RecipesService/Reducers/RecipesService.Load.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents
        import RecipeKit

        extension RecipesService {
            /// Loads a page of recipes, newest first.
            struct Load: GraniteReducer {
                typealias Center = RecipesService.Center
                init() {}

                struct Meta: GranitePayload {
                    let ticket: UUID
                    let page: Int
                }

                @Payload var meta: Meta?

                /// Marks the work's start; the state changes through `set` when it ends.
                func reduce(state: inout Center.State) {
                    guard meta != nil else { return }
                    state.loading = "load"
                    state.lastError = nil
                }

                func effect(state: Center.State) -> GraniteEffect {
                    guard let meta else { return .none }
                    let service = Live.service(RecipesService.self)
                    let ticket = meta.ticket
                    let page = meta.page
                    return .run {
                        do {
                            let value: [Recipe] = try await RecipesService.lane.run { try await RecipeClient.current.recipes(page: page) }
                            service.set(.recipes(value))
                            service.set(.loading(nil))
                            await RecipesService.tickets.resolve(ticket, with: .recipes(value))
                        } catch {
                            service.set(.failed(error.localizedDescription))
                            await RecipesService.tickets.fail(ticket, error)
                        }
                    }
                }

                var thread: DispatchQueue? { .main }
            }
        }
        """##,
        "Services/RecipesService/Reducers/RecipesService.More.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents
        import RecipeKit

        extension RecipesService {
            /// Adds the next page.
            struct More: GraniteReducer {
                typealias Center = RecipesService.Center
                init() {}

                struct Meta: GranitePayload {
                    let ticket: UUID
                    let page: Int
                }

                @Payload var meta: Meta?

                /// Marks the work's start; the state changes through `set` when it ends.
                func reduce(state: inout Center.State) {
                    guard meta != nil else { return }
                    state.loading = "more"
                    state.lastError = nil
                }

                func effect(state: Center.State) -> GraniteEffect {
                    guard let meta else { return .none }
                    let service = Live.service(RecipesService.self)
                    let ticket = meta.ticket
                    let page = meta.page
                    return .run {
                        do {
                            let value: [Recipe] = try await RecipesService.lane.run { try await RecipeClient.current.recipes(page: page) }
                            service.set(.appendRecipes(value))
                            service.set(.loading(nil))
                            await RecipesService.tickets.resolve(ticket, with: .recipes(value))
                        } catch {
                            service.set(.failed(error.localizedDescription))
                            await RecipesService.tickets.fail(ticket, error)
                        }
                    }
                }

                var thread: DispatchQueue? { .main }
            }
        }
        """##,
        "Services/RecipesService/Reducers/RecipesService.Favor.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents
        import RecipeKit

        extension RecipesService {
            /// Marks a recipe as a favorite.
            struct Favor: GraniteReducer {
                typealias Center = RecipesService.Center
                init() {}

                struct Meta: GranitePayload {
                    let ticket: UUID
                    let id: Int
                }

                @Payload var meta: Meta?

                /// Marks the work's start; the state changes through `set` when it ends.
                func reduce(state: inout Center.State) {
                    guard meta != nil else { return }
                    state.loading = "favor"
                    state.lastError = nil
                }

                func effect(state: Center.State) -> GraniteEffect {
                    guard let meta else { return .none }
                    let service = Live.service(RecipesService.self)
                    let ticket = meta.ticket
                    let id = meta.id
                    return .run {
                        do {
                            _ = try await RecipeClient.current.favorite(id: id)
                            service.set(.loading(nil))
                            await RecipesService.tickets.resolve(ticket, with: .done)
                        } catch {
                            service.set(.failed(error.localizedDescription))
                            await RecipesService.tickets.fail(ticket, error)
                        }
                    }
                }

                var thread: DispatchQueue? { .main }
            }
        }
        """##,
        "Services/RecipesService/Ops/RecipesOps.swift": ##"""
        import Foundation
        import RecipeKit

        /// Every change to RecipesService's state, as one function a test can run without a relay.
        enum RecipesOps {
            static func apply(_ kind: RecipesService.Set.Meta.Kind, to state: inout RecipesService.Center.State) {
                switch kind {
                case .recipes(let value):
                    state.recipes = value
                case .appendRecipes(let value):
                    state.recipes.append(contentsOf: value)
                case .loading(let key):
                    state.loading = key
                    if key != nil { state.lastError = nil }
                case .failed(let message):
                    state.lastError = message
                    state.loading = nil
                case .clear:
                    state = .init()
                }
            }
        }
        """##,
        "Services/EnvironmentService/EnvironmentService.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents

        /// Where the app is in its boot: idle until the root boots it, then ready, or failed with the reason.
        struct EnvironmentService: GraniteService {
            @Service(.online) var center: Center

            init() {}

            /// What the service's work answers whoever asked for it.
            enum Reply: Sendable {
                case done
            }

            static let tickets = GraniteTickets<Reply>()
        }

        extension EnvironmentService: @unchecked Sendable {}

        extension EnvironmentService {
            /// Changes the state through its one writer, on main.
            func set(_ kind: Set.Meta.Kind) {
                let service = self
                onMain { service.center.set.send(Set.Meta(kind: kind)) }
            }

            /// Boots the app: marks the start, then the phase it reached.
            func boot(isFirstLaunch: Bool) async throws {
                let ticket = await EnvironmentService.tickets.open()
                let service = self
                onMain { service.center.boot.send(Boot.Meta(ticket: ticket.id, isFirstLaunch: isFirstLaunch)) }
                _ = try await EnvironmentService.tickets.wait(ticket.id)
            }
        }
        """##,
        "Services/EnvironmentService/EnvironmentService+Center.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents

        extension EnvironmentService {
            struct Center: GraniteCenter {
                struct State: TransientState {
                    /// Where the boot is.
                    enum Phase: String, Sendable {
                        case idle
                        case ready
                        case failed
                    }

                    var phase: Phase = .idle
                    /// Whether this launch is the app's first.
                    var isFirstLaunch = false
                    /// When the app finished booting.
                    var startedAt: Date?
                    /// What is in flight, by the name of the work; nil when nothing is.
                    var loading: String?
                    /// Why the boot failed; nil once it starts again.
                    var lastError: String?

                    init() {}
                }

                @Event var set: Set.Reducer
                @Event var boot: Boot.Reducer

                @Store var state: State

                init() {}
            }
        }
        """##,
        "Services/EnvironmentService/Reducers/EnvironmentService.Set.swift": ##"""
        import Foundation
        import Granite

        extension EnvironmentService {
            /// The state's one writer: every change is a kind, applied on main by `EnvironmentOps.apply`.
            struct Set: GraniteReducer {
                typealias Center = EnvironmentService.Center
                init() {}

                struct Meta: GranitePayload {
                    enum Kind: Sendable {
                        case phase(Center.State.Phase)
                        case booted(isFirstLaunch: Bool, at: Date)
                        case loading(String?)
                        case failed(String)
                        case clear
                    }

                    var kind: Kind

                    init(kind: Kind) { self.kind = kind }
                }

                @Payload var meta: Meta?

                func reduce(state: inout Center.State) {
                    guard let meta else { return }
                    EnvironmentOps.apply(meta.kind, to: &state)
                }

                var thread: DispatchQueue? { .main }
            }
        }
        """##,
        "Services/EnvironmentService/Reducers/EnvironmentService.Boot.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents

        extension EnvironmentService {
            /// Boots the app: what was booted, and when.
            struct Boot: GraniteReducer {
                typealias Center = EnvironmentService.Center
                init() {}

                struct Meta: GranitePayload {
                    let ticket: UUID
                    let isFirstLaunch: Bool
                }

                @Payload var meta: Meta?

                /// Marks the boot's start; the state changes through `set` when it ends.
                func reduce(state: inout Center.State) {
                    guard meta != nil else { return }
                    state.loading = "boot"
                    state.lastError = nil
                }

                func effect(state: Center.State) -> GraniteEffect {
                    guard let meta else { return .none }
                    let service = Live.service(EnvironmentService.self)
                    let ticket = meta.ticket
                    let isFirstLaunch = meta.isFirstLaunch
                    return .run {
                        service.set(.booted(isFirstLaunch: isFirstLaunch, at: Date()))
                        await EnvironmentService.tickets.resolve(ticket, with: .done)
                    }
                }

                var thread: DispatchQueue? { .main }
            }
        }
        """##,
        "Services/EnvironmentService/Ops/EnvironmentOps.swift": ##"""
        import Foundation

        /// Every change to EnvironmentService's state, as one function a test can run without a relay.
        enum EnvironmentOps {
            static func apply(_ kind: EnvironmentService.Set.Meta.Kind, to state: inout EnvironmentService.Center.State) {
                switch kind {
                case .phase(let phase):
                    state.phase = phase
                case .booted(let isFirstLaunch, let date):
                    state.phase = .ready
                    state.isFirstLaunch = isFirstLaunch
                    state.startedAt = date
                    state.loading = nil
                    state.lastError = nil
                case .loading(let key):
                    state.loading = key
                    if key != nil { state.lastError = nil }
                case .failed(let message):
                    state.phase = .failed
                    state.lastError = message
                    state.loading = nil
                case .clear:
                    state = .init()
                }
            }
        }
        """##,
        "Services/LayoutService/LayoutService.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents
        import SwiftUI
        #if os(macOS)
        import AppKit
        #endif

        /// Where the app is: the destination on screen, whether the window is compact or expanded, and what the detail
        /// pane shows. Pages, menus and the root move the app through it.
        struct LayoutService: GraniteService {
            @Service(.online) var center: Center

            init() {}

            /// The Mac window's width with the detail pane closed, and open.
            static let compactWidth: CGFloat = 720
            static let expandedWidth: CGFloat = 1200
            /// The least the Mac window may be.
            static let minimumWidth: CGFloat = 640
            static let minimumHeight: CGFloat = 480
        }

        extension LayoutService: @unchecked Sendable {}

        extension LayoutService {
            /// Changes where the app is through its one writer, on main.
            func set(_ kind: Set.Meta.Kind) {
                let service = self
                onMain { service.center.set.send(Set.Meta(kind: kind)) }
            }

            /// A binding to a field of the layout, written through `set`: `layout.binding(\.destination) { .destination($0) }`.
            func binding<Value>(_ keyPath: KeyPath<Center.State, Value>, _ kind: @escaping (Value) -> Set.Meta.Kind) -> Binding<Value> {
                Binding(get: { self.state[keyPath: keyPath] }, set: { self.set(kind($0)) })
            }

            /// Goes to `destination`.
            func select(_ destination: AppDestination) {
                set(.destination(destination))
            }

            /// Shows `id` in the detail pane.
            func show(detail id: String) {
                set(.detail(id))
            }

            /// Closes the detail pane.
            func closeDetail() {
                set(.detail(nil))
            }

            #if os(macOS)
            /// Sets the key window's width, keeping its left edge, in a hop to main: AppKit is main-only.
            static func resizeWindow(width: CGFloat) {
                Task { @MainActor in
                    guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else { return }
                    var frame = window.frame
                    frame.size.width = max(width, window.minSize.width)
                    window.setFrame(frame, display: true, animate: true)
                }
            }
            #endif
        }
        """##,
        "Services/LayoutService/LayoutService+Center.swift": ##"""
        import Foundation
        import Granite
        import GraniteAgents

        extension LayoutService {
            struct Center: GraniteCenter {
                struct State: GraniteState {
                    /// The destination on screen: the one a launch asks for (`-destination search`), else the first.
                    var destination: AppDestination = AppDestination.launchArgument ?? .recipes
                    /// Whether the window is compact (a tab bar) or expanded (a sidebar beside the page).
                    var style: LayoutStyle = .compact
                    /// What the detail pane shows, by id; nil when it is closed.
                    var detail: String?

                    init() {}

                    enum CodingKeys: String, CodingKey {
                        case destination
                    }

                    /// Only the destination is kept between launches; one the app no longer has reads as the first, and
                    /// one a launch asks for wins over both.
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        destination = AppDestination.launchArgument
                            ?? (try? container.decodeIfPresent(AppDestination.self, forKey: .destination)) ?? .recipes
                    }
                }

                @Event var set: Set.Reducer

                @Store(persist: "persistence.Supper.layout.0001", autoSave: true, preload: true) var state: State

                init() {}
            }
        }
        """##,
        "Services/LayoutService/Reducers/LayoutService.Set.swift": ##"""
        import Foundation
        import Granite

        extension LayoutService {
            /// The layout's one writer: every change is a kind, applied by `LayoutOps.apply` in the turn it is sent.
            struct Set: GraniteReducer {
                typealias Center = LayoutService.Center
                init() {}

                struct Meta: GranitePayload {
                    enum Kind: Sendable {
                        case destination(AppDestination)
                        case style(LayoutStyle)
                        case detail(String?)
                        case clear
                    }

                    var kind: Kind

                    init(kind: Kind) { self.kind = kind }
                }

                @Payload var meta: Meta?

                func reduce(state: inout Center.State) {
                    guard let meta else { return }
                    LayoutOps.apply(meta.kind, to: &state)
                }

                var thread: DispatchQueue? { nil }
            }
        }
        """##,
        "Services/LayoutService/Ops/LayoutOps.swift": ##"""
        import Foundation

        /// Every change to where the app is, as one function a test can run without a relay.
        enum LayoutOps {
            static func apply(_ kind: LayoutService.Set.Meta.Kind, to state: inout LayoutService.Center.State) {
                switch kind {
                case .destination(let destination):
                    state.destination = destination
                    state.detail = nil
                case .style(let style):
                    state.style = style
                case .detail(let id):
                    state.detail = id
                case .clear:
                    state = .init()
                }
            }
        }
        """##,
        "Components/RecipeList/RecipeList.swift": ##"""
        import Granite
        import SwiftUI
        import RecipeKit

        struct RecipeList: GraniteComponent {
            @Command var center: Center

            @Relay var recipes: RecipesService
            @Relay var layout: LayoutService
        }
        """##,
        "Components/RecipeList/RecipeList+Center.swift": ##"""
        import Foundation
        import Granite
        import RecipeKit

        extension RecipeList {
            /// State only this page's own controls touch; what another page, a menu or the root reads lives in a service.
            struct Center: GraniteCenter {
                struct State: GraniteState {}

                @Store var state: State
            }
        }
        """##,
        "Components/RecipeList/RecipeList+View.swift": ##"""
        import Granite
        import SwiftUI
        import RecipeKit

        extension RecipeList: View {
            var view: some View {
                List {
                    ForEach(recipes.state.recipes) { recipe in
                        RecipeListRowView(recipe: recipe)
                            .contextMenu {
                                Button("Favorite", systemImage: "star") { Task { try? await favor(recipe: recipe) } }
                            }
                            #if os(iOS)
                            .swipeActions {
                                Button("Favorite", systemImage: "star") { Task { try? await favor(recipe: recipe) } }
                            }
                            #endif
                            .onAppear {
                                if recipe.id == recipes.state.recipes.last?.id, recipes.state.loading == nil { Task { try? await more() } }
                            }
                    }
                }
                .listStyle(.plain)
                .overlay { status }
                .safeAreaInset(edge: .top, spacing: 0) { errorBanner }
                .navigationTitle("Recipes")
                .refreshable { try? await refresh() }
                .toolbar {
                    #if os(macOS)
                    ToolbarItem {
                        Button { Task { try? await refresh() } } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .keyboardShortcut("r")
                    }
                    #endif
                }
                .task(id: isReady) {
                    guard isReady, recipes.state.recipes.isEmpty else { return }
                    try? await refresh()
                }
            }

            @ViewBuilder
            private var status: some View {
                if recipes.state.recipes.isEmpty {
                    if recipes.state.loading != nil {
                        ProgressView()
                    } else {
                        ContentUnavailableView("No recipes yet", systemImage: "tray")
                    }
                }
            }

            @ViewBuilder
            private var errorBanner: some View {
                if let message = recipes.state.lastError {
                    HStack(spacing: 8) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                        Spacer(minLength: 8)
                        Button("Try Again") { Task { try? await refresh() } }
                            .buttonStyle(.borderless)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.15))
                }
            }

            /// Whether every service the page reads has loaded what it keeps.
            private var isReady: Bool { recipes.isLoaded }
        }
        """##,
        "Components/RecipeList/RecipeList+Actions.swift": ##"""
        import Foundation
        import Granite
        import SwiftUI
        import RecipeKit

        extension RecipeList {
            func refresh() async throws {
                try await recipes.load(page: 1)
            }

            func more() async throws {
                try await recipes.more(page: recipes.state.recipes.count / 20 + 2)
            }

            func favor(recipe: Recipe) async throws {
                try await recipes.favor(id: recipe.id)
            }

            func browseCooks() async throws {
                layout.select(.settings)
            }

            func surprise() async throws {
                let pick = recipes.state.recipes.randomElement()
                layout.show(detail: pick.map { String($0.id) } ?? "")
            }
        }
        """##,
        "Components/Settings/Settings.swift": ##"""
        import Granite
        import SwiftUI

        struct Settings: GraniteComponent {
            @Command var center: Center

            @Relay var config: ConfigService

            /// Re-draws the page within a frame of a change to the services its controls are bound to.
            @StateObject private var clock = RelayClock([RelayClock.on(ConfigService.self)])
        }
        """##,
        "Components/Settings/Settings+Center.swift": ##"""
        import Foundation
        import Granite

        extension Settings {
            /// State only this page's own controls touch; what another page, a menu or the root reads lives in a service.
            struct Center: GraniteCenter {
                struct State: GraniteState {}

                @Store var state: State
            }
        }
        """##,
        "Components/Settings/Settings+View.swift": ##"""
        import Granite
        import SwiftUI

        extension Settings: View {
            var view: some View {
                Form {
                    Section("Appearance") {
                        Picker("Theme", selection: config.binding(\.appearance) { .appearance($0) }) {
                            ForEach(AppAppearance.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .safeAreaInset(edge: .top, spacing: 0) { errorBanner }
                .navigationTitle("Settings")
            }

            @ViewBuilder
            private var errorBanner: some View {
                if let message = config.state.lastError {
                    HStack(spacing: 8) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.15))
                }
            }
        }
        """##,
        "Tests/RecipesOpsTests.swift": ##"""
        import Foundation
        import Testing
        @testable import Supper

        /// RecipesService's state changes, one a kind: what its writer does, run without a relay.
        struct RecipesOpsTests {
            @Test func writesRecipes() {
                var state = RecipesService.Center.State()
                let value: [Recipe] = [Recipe.preview]
                RecipesOps.apply(.recipes(value), to: &state)
                #expect(state.recipes == value)
            }

            @Test func appendsToRecipes() {
                var state = RecipesService.Center.State()
                let page: [Recipe] = [Recipe.preview]
                RecipesOps.apply(.appendRecipes(page), to: &state)
                RecipesOps.apply(.appendRecipes(page), to: &state)
                #expect(state.recipes == page + page)
            }

            @Test func workInFlightIsMarked() {
                var state = RecipesService.Center.State()
                RecipesOps.apply(.failed("offline"), to: &state)
                RecipesOps.apply(.loading("load"), to: &state)
                #expect(state.loading == "load")
                #expect(state.lastError == nil)
            }

            @Test func aFailureSaysWhyAndEndsTheWork() {
                var state = RecipesService.Center.State()
                RecipesOps.apply(.loading("load"), to: &state)
                RecipesOps.apply(.failed("offline"), to: &state)
                #expect(state.lastError == "offline")
                #expect(state.loading == nil)
            }

            @Test func clearStartsOver() {
                var state = RecipesService.Center.State()
                RecipesOps.apply(.loading("load"), to: &state)
                RecipesOps.apply(.clear, to: &state)
                #expect(state == RecipesService.Center.State())
            }
        }
        """##,
        "UITests/SupperUITests.swift": ##"""
        import XCTest

        /// The app as a person meets it: launched, and on screen.
        final class SupperUITests: XCTestCase {
            override func setUpWithError() throws {
                continueAfterFailure = false
            }

            @MainActor
            func testLaunches() throws {
                let app = XCUIApplication()
                app.launch()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            }
        }
        """##,
        "Packages/RecipeKit/api.json": ##"""
        {
          "auth": "none",
          "baseURL": "https://api.supper.example",
          "coding": "snake",
          "dates": [],
          "endpoints": [
            "GET /v1/recipes?page,per_page -> [Recipe] as recipes paged \"the newest recipes first\"",
            "GET /v1/recipes/{id:Int} -> Recipe as recipe",
            "POST /v1/recipes/{id:Int}/favorite -> Recipe as favorite \"marks a recipe as a favorite\"",
            "GET /v1/cooks?page -> [Cook] as cooks paged"
          ],
          "entities": [
            "Recipe \"a dish someone shared\": id Int, title String, minutes Int = 30, cook Cook, favorite Bool = false, added Date",
            "Cook \"someone who shares recipes\": id Int, name String, avatar URL?, recipes Int = 0"
          ],
          "feeds": false,
          "files": [],
          "name": "RecipeKit",
          "paging": "page"
        }
        """##,
        "Packages/RecipeKit/Sources/RecipeKit/RecipeClient.swift": ##"""
        import Foundation
        import os

        /// The typed client of the Supper API: where it sends (`baseURL`, which may change while the app runs, so one client
        /// follows the server a person picks), how it signs requests (`auth`, with the token kept per host in `tokens`), how
        /// it reads and writes JSON, and when it tries a failed request again.
        ///
        /// ```swift
        /// let client = RecipeClient(baseURL: URL(string: "https://api.supper.example")!)
        /// client.baseURL = URL(string: "https://another.example")!   // every request after goes there
        /// ```
        ///
        /// Each endpoint is a method (`Endpoints/`); `send(_:)` sends any other `Request`.
        public final class RecipeClient: Sendable {
            /// The base URL a client starts at unless it is given another: `https://api.supper.example`.
            public static let defaultBaseURL = URL(string: "https://api.supper.example")!

            /// How a request proves who sends it.
            public let auth: AuthScheme
            /// Where the tokens are kept, one a host.
            public let tokens: any TokenStore
            /// What carries the requests.
            public let transport: any HTTPTransport
            /// When a failed request is sent again.
            public let retry: RetryPolicy
            /// Reads the answers: `RecipeCoding.decoder()` unless the client was given another.
            public let decoder: JSONDecoder
            /// Writes the bodies: `RecipeCoding.encoder()` unless the client was given another.
            public let encoder: JSONEncoder

            private struct State: Sendable {
                var baseURL: URL
                var headers: [String: String]
            }

            private let state: OSAllocatedUnfairLock<State>

            public init(baseURL: URL = RecipeClient.defaultBaseURL, auth: AuthScheme = .none, tokens: any TokenStore = KeychainTokenStore(),
                        transport: any HTTPTransport = URLSessionTransport(), retry: RetryPolicy = .standard,
                        decoder: JSONDecoder = RecipeCoding.decoder(), encoder: JSONEncoder = RecipeCoding.encoder(),
                        headers: [String: String] = [:]) {
                self.state = OSAllocatedUnfairLock(initialState: State(baseURL: baseURL, headers: headers))
                self.auth = auth
                self.tokens = tokens
                self.transport = transport
                self.retry = retry
                self.decoder = decoder
                self.encoder = encoder
            }

            /// Where requests go: a scheme, a host and, optionally, a path each endpoint's path is added to.
            public var baseURL: URL {
                get { state.withLock { $0.baseURL } }
                set { state.withLock { $0.baseURL = newValue } }
            }

            /// Headers every request carries beside its own: a `User-Agent`, an app version.
            public var headers: [String: String] {
                get { state.withLock { $0.headers } }
                set { state.withLock { $0.headers = newValue } }
            }

            /// A client like this one that sends to `baseURL`: the same transport, tokens, retries and coding.
            public func withBaseURL(_ baseURL: URL) -> RecipeClient {
                RecipeClient(baseURL: baseURL, auth: auth, tokens: tokens, transport: transport, retry: retry, decoder: decoder,
                               encoder: encoder, headers: headers)
            }

            /// `example.com`, `https://example.com/` or `http://localhost:8080` as a base URL: `https` when the text names no
            /// scheme; nil when it names no host.
            public static func url(from text: String) -> URL? {
                var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                if !text.contains("://") { text = "https://" + text }
                while text.hasSuffix("/") { text.removeLast() }
                guard let url = URL(string: text), url.host != nil, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                    return nil
                }
                return url
            }
        }
        """##,
        "Packages/RecipeKit/Sources/RecipeKit/Coding/RecipeCoding.swift": ##"""
        import Foundation

        /// How the Supper API's JSON is read and written. Dates are read in ISO 8601, with or without fractional seconds
        /// and a zone (a stamp with no zone is UTC); a number is read as seconds since 1970. Dates are written
        /// in ISO 8601. Keys are each type's own (`CodingKeys`).
        public enum RecipeCoding {
            /// The `DateFormatter` patterns the API writes dates in beside ISO 8601.
            public static let dateFormats: [String] = []

            /// A decoder for the API's responses.
            public static func decoder() -> JSONDecoder {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    if let number = try? container.decode(Double.self) {
                        return Date(timeIntervalSince1970: number)
                    }
                    let text = try container.decode(String.self)
                    guard let date = date(from: text) else {
                        throw DecodingError.dataCorruptedError(in: container, debugDescription: "`\(text)` is not a date the API writes")
                    }
                    return date
                }
                return decoder
            }

            /// An encoder for the API's request bodies.
            public static func encoder() -> JSONEncoder {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                return encoder
            }

            /// `text` read as a date: ISO 8601 first, then each of `dateFormats`.
            public static func date(from text: String) -> Date? {
                if let date = DateParsing.iso8601(text) { return date }
                for formatter in formatters {
                    if let date = formatter.date(from: text) { return date }
                }
                return nil
            }

            private static let formatters: [DateFormatter] = dateFormats.map(formatter)

            private static func formatter(_ format: String) -> DateFormatter {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                return formatter
            }
        }
        """##,
        "Packages/RecipeKit/Sources/RecipeKit/Endpoints/Recipes.swift": ##"""
        import Foundation

        extension RecipeClient {
            /// The newest recipes first.
            ///
            /// `GET /v1/recipes`; every page: `recipesPages(…)`.
            public func recipes(page: Int? = nil, perPage: Int? = nil) async throws -> [Recipe] {
                try await send(Request<[Recipe]>(.get, "/v1/recipes", query: ["page": page, "per_page": perPage]))
            }

            /// Every page of `recipes(…)`, from page `page` on, one request a page: an empty page, or one shorter than
            /// `perPage`, ends it.
            public func recipesPages(from page: Int = 1, perPage: Int? = nil) -> Pages<Recipe> {
                Pages(from: page) { [self] number in
                    let items = try await recipes(page: number, perPage: perPage)
                    let last = items.isEmpty || perPage.map { items.count < $0 } == true
                    return Page(items: items, number: number, next: last ? nil : number + 1)
                }
            }

            /// `GET /v1/recipes/{id}`
            public func recipe(id: Int) async throws -> Recipe {
                try await send(Request<Recipe>(.get, "/v1/recipes/{id}", parameters: ["id": id]))
            }

            /// Marks a recipe as a favorite.
            ///
            /// `POST /v1/recipes/{id}/favorite`
            @discardableResult
            public func favorite(id: Int) async throws -> Recipe {
                try await send(Request<Recipe>(.post, "/v1/recipes/{id}/favorite", parameters: ["id": id]))
            }
        }
        """##,
        "Packages/RecipeKit/Sources/RecipeKit/Endpoints/Cooks.swift": ##"""
        import Foundation

        extension RecipeClient {
            /// `GET /v1/cooks`; every page: `cooksPages(…)`.
            public func cooks(page: Int? = nil) async throws -> [Cook] {
                try await send(Request<[Cook]>(.get, "/v1/cooks", query: ["page": page]))
            }

            /// Every page of `cooks(…)`, from page `page` on, one request a page: an empty page ends it.
            public func cooksPages(from page: Int = 1) -> Pages<Cook> {
                Pages(from: page) { [self] number in
                    let items = try await cooks(page: number)
                    let last = items.isEmpty
                    return Page(items: items, number: number, next: last ? nil : number + 1)
                }
            }
        }
        """##,
        "Packages/RecipeKit/Sources/RecipeKit/Models/Recipe.swift": ##"""
        import Foundation

        /// A dish someone shared.
        public struct Recipe: Codable, Hashable, Identifiable, Sendable {
            public var id: Int
            public var title: String
            public var minutes: Int
            public var cook: Cook
            public var favorite: Bool
            public var added: Date

            public init(id: Int, title: String, minutes: Int = 30, cook: Cook, favorite: Bool = false, added: Date) {
                self.id = id
                self.title = title
                self.minutes = minutes
                self.cook = cook
                self.favorite = favorite
                self.added = added
            }

            enum CodingKeys: String, CodingKey {
                case id
                case title
                case minutes
                case cook
                case favorite
                case added
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(Int.self, forKey: .id)
                title = try container.decode(String.self, forKey: .title)
                minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 30
                cook = try container.decode(Cook.self, forKey: .cook)
                favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
                added = try container.decode(Date.self, forKey: .added)
            }
        }

        extension Recipe {
            /// A Recipe to preview and test with.
            public static let preview: Recipe = Recipe(
                id: 1,
                title: "Sample title",
                minutes: 42,
                cook: Cook.preview,
                favorite: false,
                added: Date(timeIntervalSince1970: 1_767_225_600)
            )
        }
        """##,
        "Packages/RecipeKit/Sources/RecipeKit/Models/Cook.swift": ##"""
        import Foundation

        /// Someone who shares recipes.
        public struct Cook: Codable, Hashable, Identifiable, Sendable {
            public var id: Int
            public var name: String
            public var avatar: URL?
            public var recipes: Int

            public init(id: Int, name: String, avatar: URL? = nil, recipes: Int = 0) {
                self.id = id
                self.name = name
                self.avatar = avatar
                self.recipes = recipes
            }

            enum CodingKeys: String, CodingKey {
                case id
                case name
                case avatar
                case recipes
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(Int.self, forKey: .id)
                name = try container.decode(String.self, forKey: .name)
                avatar = try container.decodeIfPresent(URL.self, forKey: .avatar)
                recipes = try container.decodeIfPresent(Int.self, forKey: .recipes) ?? 0
            }
        }

        extension Cook {
            /// A Cook to preview and test with.
            public static let preview: Cook = Cook(
                id: 1,
                name: "Sample name",
                avatar: URL(string: "https://example.com/avatar")!,
                recipes: 42
            )
        }
        """##,
        "Shared/Utility/RecipeClient+Current.swift": ##"""
        import Foundation
        import RecipeKit

        extension RecipeClient {
            /// The client the app's services send through: the live API, or the preview's sample answers when the app runs
            /// on mocks (`-mock YES` or `MOCK=1`), so its screens, tests and screenshots need no server.
            nonisolated(unsafe) static var current: RecipeClient = isMocked ? .preview : RecipeClient()

            /// Whether the app runs on mock backend responses.
            static var isMocked: Bool {
                UserDefaults.standard.bool(forKey: "mock") || ProcessInfo.processInfo.environment["MOCK"] == "1"
            }
        }
        """##,
        "Supper.xcodeproj/xcshareddata/xcschemes/Supper-iOS.xcscheme": ##"""
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme
           LastUpgradeVersion = "2660"
           version = "1.7">
           <BuildAction
              parallelizeBuildables = "YES"
              buildImplicitDependencies = "YES"
              buildArchitectures = "Automatic">
              <BuildActionEntries>
                 <BuildActionEntry
                    buildForTesting = "YES"
                    buildForRunning = "YES"
                    buildForProfiling = "YES"
                    buildForArchiving = "YES"
                    buildForAnalyzing = "YES">
                    <BuildableReference
                       BuildableIdentifier = "primary"
                       BlueprintIdentifier = "3EC43326E940A556DF4396D2"
                       BuildableName = "Supper.app"
                       BlueprintName = "Supper-iOS"
                       ReferencedContainer = "container:Supper.xcodeproj">
                    </BuildableReference>
                 </BuildActionEntry>
              </BuildActionEntries>
           </BuildAction>
           <TestAction
              buildConfiguration = "Debug"
              selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
              selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
              shouldUseLaunchSchemeArgsEnv = "YES">
              <Testables>
                 <TestableReference
                    skipped = "NO"
                    parallelizable = "NO">
                    <BuildableReference
                       BuildableIdentifier = "primary"
                       BlueprintIdentifier = "35FD5C6DFD9FC5921532E3A1"
                       BuildableName = "SupperTests.xctest"
                       BlueprintName = "SupperTests-iOS"
                       ReferencedContainer = "container:Supper.xcodeproj">
                    </BuildableReference>
                 </TestableReference>
                 <TestableReference
                    skipped = "YES"
                    parallelizable = "NO">
                    <BuildableReference
                       BuildableIdentifier = "primary"
                       BlueprintIdentifier = "BA1C58D710B2433B5A950BD8"
                       BuildableName = "SupperUITests.xctest"
                       BlueprintName = "SupperUITests-iOS"
                       ReferencedContainer = "container:Supper.xcodeproj">
                    </BuildableReference>
                 </TestableReference>
              </Testables>
           </TestAction>
           <LaunchAction
              buildConfiguration = "Debug"
              selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
              selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
              launchStyle = "0"
              useCustomWorkingDirectory = "NO"
              ignoresPersistentStateOnLaunch = "NO"
              debugDocumentVersioning = "YES"
              debugServiceExtension = "internal"
              allowLocationSimulation = "YES">
              <BuildableProductRunnable
                 runnableDebuggingMode = "0">
                 <BuildableReference
                    BuildableIdentifier = "primary"
                    BlueprintIdentifier = "3EC43326E940A556DF4396D2"
                    BuildableName = "Supper.app"
                    BlueprintName = "Supper-iOS"
                    ReferencedContainer = "container:Supper.xcodeproj">
                 </BuildableReference>
              </BuildableProductRunnable>
           </LaunchAction>
           <ProfileAction
              buildConfiguration = "Release"
              shouldUseLaunchSchemeArgsEnv = "YES"
              savedToolIdentifier = ""
              useCustomWorkingDirectory = "NO"
              debugDocumentVersioning = "YES">
              <BuildableProductRunnable
                 runnableDebuggingMode = "0">
                 <BuildableReference
                    BuildableIdentifier = "primary"
                    BlueprintIdentifier = "3EC43326E940A556DF4396D2"
                    BuildableName = "Supper.app"
                    BlueprintName = "Supper-iOS"
                    ReferencedContainer = "container:Supper.xcodeproj">
                 </BuildableReference>
              </BuildableProductRunnable>
           </ProfileAction>
           <AnalyzeAction
              buildConfiguration = "Debug">
           </AnalyzeAction>
           <ArchiveAction
              buildConfiguration = "Release"
              revealArchiveInOrganizer = "YES">
           </ArchiveAction>
        </Scheme>
        """##,
        "Supper.xcodeproj/xcshareddata/xcschemes/Supper-macOS.xcscheme": ##"""
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme
           LastUpgradeVersion = "2660"
           version = "1.7">
           <BuildAction
              parallelizeBuildables = "YES"
              buildImplicitDependencies = "YES"
              buildArchitectures = "Automatic">
              <BuildActionEntries>
                 <BuildActionEntry
                    buildForTesting = "YES"
                    buildForRunning = "YES"
                    buildForProfiling = "YES"
                    buildForArchiving = "YES"
                    buildForAnalyzing = "YES">
                    <BuildableReference
                       BuildableIdentifier = "primary"
                       BlueprintIdentifier = "C8F252DFE6FCAF263F614C58"
                       BuildableName = "Supper.app"
                       BlueprintName = "Supper-macOS"
                       ReferencedContainer = "container:Supper.xcodeproj">
                    </BuildableReference>
                 </BuildActionEntry>
              </BuildActionEntries>
           </BuildAction>
           <TestAction
              buildConfiguration = "Debug"
              selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
              selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
              shouldUseLaunchSchemeArgsEnv = "YES">
              <Testables>
                 <TestableReference
                    skipped = "NO"
                    parallelizable = "NO">
                    <BuildableReference
                       BuildableIdentifier = "primary"
                       BlueprintIdentifier = "CCADCA29B31C701E0705CAD9"
                       BuildableName = "SupperTests.xctest"
                       BlueprintName = "SupperTests-macOS"
                       ReferencedContainer = "container:Supper.xcodeproj">
                    </BuildableReference>
                 </TestableReference>
                 <TestableReference
                    skipped = "YES"
                    parallelizable = "NO">
                    <BuildableReference
                       BuildableIdentifier = "primary"
                       BlueprintIdentifier = "E9BC4A7917CCC4E1D007B4D8"
                       BuildableName = "SupperUITests.xctest"
                       BlueprintName = "SupperUITests-macOS"
                       ReferencedContainer = "container:Supper.xcodeproj">
                    </BuildableReference>
                 </TestableReference>
              </Testables>
           </TestAction>
           <LaunchAction
              buildConfiguration = "Debug"
              selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
              selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
              launchStyle = "0"
              useCustomWorkingDirectory = "NO"
              ignoresPersistentStateOnLaunch = "NO"
              debugDocumentVersioning = "YES"
              debugServiceExtension = "internal"
              allowLocationSimulation = "YES">
              <BuildableProductRunnable
                 runnableDebuggingMode = "0">
                 <BuildableReference
                    BuildableIdentifier = "primary"
                    BlueprintIdentifier = "C8F252DFE6FCAF263F614C58"
                    BuildableName = "Supper.app"
                    BlueprintName = "Supper-macOS"
                    ReferencedContainer = "container:Supper.xcodeproj">
                 </BuildableReference>
              </BuildableProductRunnable>
           </LaunchAction>
           <ProfileAction
              buildConfiguration = "Release"
              shouldUseLaunchSchemeArgsEnv = "YES"
              savedToolIdentifier = ""
              useCustomWorkingDirectory = "NO"
              debugDocumentVersioning = "YES">
              <BuildableProductRunnable
                 runnableDebuggingMode = "0">
                 <BuildableReference
                    BuildableIdentifier = "primary"
                    BlueprintIdentifier = "C8F252DFE6FCAF263F614C58"
                    BuildableName = "Supper.app"
                    BlueprintName = "Supper-macOS"
                    ReferencedContainer = "container:Supper.xcodeproj">
                 </BuildableReference>
              </BuildableProductRunnable>
           </ProfileAction>
           <AnalyzeAction
              buildConfiguration = "Debug">
           </AnalyzeAction>
           <ArchiveAction
              buildConfiguration = "Release"
              revealArchiveInOrganizer = "YES">
           </ArchiveAction>
        </Scheme>
        """##,
    ]
}
