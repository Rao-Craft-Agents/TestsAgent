# Testing TestsAgent

How `tests` is tested: its own suite, and its gated test, which makes a real app through the family's installed
runners, writes its tests, and runs them on the Mac and on the iOS simulator. Every test it writes runs on mock
backend responses, never a live service.

## The suite

```
swift test                                        # 39 tests (the gated one skipped), 20 to 45 s on a busy Mac
TESTS_BUILD=1 swift test --filter TestsBuildTests # the output built and run for real (gated, about 3½ minutes)
```

| Suite | What it holds |
|---|---|
| `TestsAgentTests` | the record found through the roster, the exact schema, a note per field, the guide's modes, a call through `AnyAgentPackage.perform` that writes every file it names; the host's folder used when the JSON names none |
| `ReadTests` | the project read by `plutil`; a service's fields, store key, work, writes, loading keys, Ops and helpers; a client package's endpoints, paging and previews; a seam and whether a test can assign it (`var`, `let`, computed with and without a setter, a client made in the work); a page's relays, actions and title; the destinations; sample values |
| `EmitTests` | each piece of work in each scenario; a work with no backend checked against its Ops; scenarios narrowing what is written; the root; the server (pages then nothing, never the network); a `mocks` `.mock()` used when the package has one; pages drawn in every state and driven; a launch a destination; an app with no destinations; a work the tests cannot mock left out with a note; everything parses; refusals naming every reason and writing nothing; a file it did not write never overwritten |
| `EditTests` | no page while the app hosts its tests; stores keyed apart; a forgotten package import added; a second call making no edit twice; each edit on its own |
| `ExpectAskTests` | an action the code does not say asked of a scripted model, wrong answers sent back with what was wrong, the right one landing; the prompt naming what the test has; an answer that never comes right left out with a note; no model, a note |

The unit fixture (`Support/AppFixture.swift`) is an app as `granite` and `network` write one, trimmed to what the
agent reads: a recipe app, Supper, with a persisted service of three pieces of work, a boot service, a layout service
with helpers, two pages and three destinations.

## The gated build test

`TestsBuildTests` makes Trailhead, a hiking app, the way Craft's turns would: each layer by its agent's installed
runner (`~/.rao/apps/craft/agents/<Name>/agent`, one JSON line in, from inside the app's folder with `directory`
set) — granite's project, network's `TrailKit` (trails paged, a trail, save a trail, huts paged), the services
`Trails` (persisted; load, more, save) and `Huts` (load), the pages `TrailList`, `HutList` and `Settings`, navigation
with three destinations — and the glue a turn's model writes: `TrailClient.current`, the preview's answers on mocks.
Then:

1. `tests` writes the layer (`{}`) in under a second: 22 files, 29 tests (17 of the services' work, 8 of the pages, 1 of the boot,
   3 launches).
2. `xcodebuild -scheme Trailhead-macOS -destination platform=macOS test` runs them with granite's Ops tests: 48 tests
   in 12 suites pass in about 5 s, and the app's container holds only the tests' own stores (`….tests`), never a
   person's.
3. `xcodebuild -scheme Trailhead-iOS -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test` runs the same
   48 unit tests hosted on the simulator, the three launch tests (`-mock YES -destination <case>`) and granite's own
   launch test (now on mocks too), headless.
4. A copy whose `TrailsService.More` replaces the list instead of adding the page fails exactly the four tests of
   load-more, each on its own expectation, and nothing else:

   ```
   moreAddsTheNextPageToTrails                     root.trails.state.trails == first + next
   moreWithNothingLeftKeepsTrails                  root.trails.state.trails == first
   aFailedMoreKeepsTrailsAndATryAgainAddsThePage   root.trails.state.trails == first + next
   moreAddsToTrails (TrailListPageTests)           root.trails.state.trails.count > beforeTrails
   ```

The test takes the apps it installed off the simulator and removes what the run kept in the Mac app's container (the
container's folder itself is the system's: macOS refuses its removal).

## What the test journey found

- On iOS, `ImageRenderer` cannot flatten a `NavigationStack` (UIKit's) and SwiftUI traps ("no current update to
  enqueue action to"): pages are drawn bare. A `List` draws as a placeholder there; its view is still built.
- On iOS, `ImageRenderer` runs a page's `.task`: drawing an empty list starts the page's own refresh. The root waits
  until no service has work in flight before each test.
- A hosted test run starts the app, and its first page loaded through the live client while the tests ran, holding
  the service's lane (seen as a 1.4 s wait and a live request that failed). Hosting its unit tests, the app now shows
  no page.
- Before the store keys were kept apart, the tests wrote into the person's stores in the app's container.
- GraniteAgent dee2792: a row view naming a package's type without importing it when no action of its page names the
  type, and Ops tests naming a package's types without importing it. `tests` adds the import to test files; the
  fixture adds the row view's, as a turn's model would.
