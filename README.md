# TestsAgent

Functional tests for an app built on [Granite](https://github.com/riteshpakala/Granite), written from the app's own
code and shipped as a Granite agent package. Granite writes each service's Ops tests (its state's transitions);
`tests` writes what proves the app works: each service's work called through its ticketed entry with the backend
mocked and the state it leaves asserted, each page drawn offscreen in light and dark and its actions run, and a UI
launch test per destination. Every test runs on mock backend responses, never a live server.

It is one of the [Rao Craft Agents](https://github.com/Rao-Craft-Agents): independent packages that, tagged in prompts
along the life of a project, build an app of [Loom](https://github.com/riteshpakala/Loom)'s quality. `tests` comes
after `granite` has made the services, pages and navigation, `network` the client, and `mocks` (when installed) its
fixtures.

## How an app finds it

TestsAgent is a `GraniteAgentPackage`, and it carries a record in its binary:

```swift
@used @section("__DATA_CONST,__granite")
let testsRecord: GraniteRoster.Record = { GraniteRoster.record(TestsAgent.self) }
```

In [Craft](https://github.com/riteshpakala/Craft), install it from the Agent Store or with
`craft agents add https://github.com/Rao-Craft-Agents/TestsAgent.git`, then say `$tests` in a request:

```
$tests prove the recipe app works: its services' work on mock responses, its pages, and each tab at launch
```

The model writes the call (often `{}`); the call shows on Craft's agent map as `tests-1`, and the turn builds and runs
the tests it wrote.

## What a call takes and answers

| Field | | |
|---|---|---|
| `services` | optional | the services whose work is tested, `Recipes` or `RecipesService`; every service with work when left out, none for `[]` |
| `pages` | optional | the pages drawn and driven, `RecipeList`; every page when left out, none for `[]` |
| `ui` | optional | whether to write a UI launch test per destination; true when left out |
| `scenarios` | optional | `normal`, `empty`, `failing`, `slow`: what the mock backend answers in the service tests; all four when left out |
| `rounds` | optional | how many answers the host's model may give for what one page action leaves; 3 when left out |
| `directory` | the host's | the folder the host works in; a host fills it and does not show it to a model, and a call whose JSON leaves it out works in the folder the host offers (`AgentHost.directory`) |

The answer is a `TestsResult`: every file written or edited (`path`, `paths`, absolute), the services, pages and
destinations tested, how many tests, and a sentence for anything left out and why. Calls run one at a time (`lanes`
1): a call edits files other calls share (the app's `App`, its centers, its schemes).

## What it writes

| File | What |
|---|---|
| `Tests/Support/TestRoot.swift` | a `@MainActor` root holding a relay to every service; `boot(_:)` waits until no work is in flight, points every client the services send through at the scenario's mock, waits for persisted stores to load, and clears each service; `answer(_:)` switches the backend mid-test; `settle()`, `quiet()`, `until(_:)` |
| `Tests/Support/ServicesOnMocks.swift` | the one `@Suite(.serialized)` parent every suite nests in (relays are process singletons, and separate suites run side by side) |
| `Tests/Support/<Client>Server.swift` | when `mocks` has written no `.mock()`: an `HTTPTransport` that answers every endpoint from the package's preview values, three pages of two items each with ids of their own and then empty pages, a 500 when failing, late when slow, and keeps every request |
| `Tests/<Service>Tests.swift` | for each piece of work: the field it fills (a second page replaces the first), the next page added, nothing added past the last page, `lastError` set on a failing backend and cleared by a try again with the field kept, `loading` marked while in flight; a request reached the backend; what the Ops do with any other kind the work sets |
| `Tests/<Page>PageTests.swift` | the page drawn with `ImageRenderer` in light and dark, loaded, empty and failing; each `+Actions` function run as a tap runs it (an item from the loaded list, the page refreshed first when it needs something to act on), with the state it leaves |
| `UITests/<App>DestinationTests.swift` | one launch a destination with `-mock YES -destination <case>`, asserting its page's title comes on screen |
| `Shared/Utility/RunMode.swift` | how a launch runs: for a person, on mocks, or hosting the unit tests |

And a few edits, each made once: the app's `WindowGroup` shows its root page only when the app is not hosting its unit
tests (otherwise the pages load through the live client and race the tests on the same services); each persisted
service's store key gains `RunMode.storeSuffix` (`.tests`, or `.mock` on a mock launch), so a test never reads or
writes what a person saved; the iOS scheme runs the UI tests (the macOS scheme keeps them skipped: they need an
interactive session there); a test file that names a package's types without importing the package gets the import.

## How the tests are made

| Step | What |
|---|---|
| Read | the project (by `plutil`): the app's module, its test folders, its schemes; each service's state, store key, writer kinds, ticketed entries, work reducers (what each awaits, writes and marks in flight) and Ops; each client package `network` wrote (endpoints, answers, paging, previews, a `mocks` `.mock()`); each page's relays, inputs, title and actions; the destinations |
| Seams | where a work's call to an endpoint gets its client (`RecipeClient.current`, `Backend.recipes`, `AppRoot.shared.client`), read back to its declaration; a test assigns it. A work that sends through something a test cannot assign, or reaches the network itself, is left out with a note saying what would open it |
| Derive | arguments (page 1, then page 2; a sample of each type; an item the page lists), and every expectation that can be read off the code: the work's write, its loading key, the Ops' assignments for the kinds it sets, a page action's service calls, `set` calls and helpers that forward to `set` |
| Ask | only what a page action leaves when its code does not say (`layout.show(detail: pick.map { … } ?? "")`): the host's model answers at most three Swift boolean expressions over `root.<service>.state` and the action's arguments; each is checked against the services' real fields, parsed with `swiftc -parse`, and asked again with what was wrong; one that never comes right is left out with a note |
| Check | every file staged, parsed with `swiftc -parse`, then moved into the project together; a file at a path it writes that it did not write is refused, never overwritten |

Run them as Craft's checks do: `xcodebuild -scheme <App>-macOS -destination platform=macOS test`, and on the
simulator `xcodebuild -scheme <App>-iOS -destination 'platform=iOS Simulator,name=<iPhone>' test` (the same tests, and
the UI launch tests).

## Testing

```
swift test                                        # the record, the schema, the reading, the tests written, the edits, the model's asks
TESTS_BUILD=1 swift test --filter TestsBuildTests # an app made through the installed runners, its tests run on the Mac and the
                                                  # simulator, and a broken reducer caught (gated, minutes)
```

MIT licensed.
