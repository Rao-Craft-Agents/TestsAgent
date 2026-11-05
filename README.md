# TestsAgent

Find out whether your Granite app does what it should, each time you change it. `tests` reads the app's own services,
pages and navigation and writes the tests that prove them: each service's work run against a mock backend with the
state it leaves checked, each page drawn in light and dark with its actions run, and a launch test for each tab.
`granite` already writes each service's Ops tests, its state's transitions; `tests` writes what proves the app works,
and every test runs on mock backend responses, never a live server.

## What you can ask

```
$tests prove the recipe app works: its services' work on mock responses, its pages, and each tab at launch
$tests the Recipes service when the backend is empty, failing or slow
$tests just the RecipeList page, without the UI tests
```

Craft writes the call (often `{}`), shows it on its agent map, and the turn builds and runs the tests it wrote.

## What you get

- **Service tests on a mock backend.** For each piece of work: the field it fills, the next page added and nothing
  added past the last, an error set on a failing backend and cleared by a try again, and loading marked while it runs,
  in four scenarios: normal, empty, failing and slow.
- **Page tests.** Each page drawn offscreen in light and dark, loaded, empty and failing, and each of its actions run
  as a tap runs it, with the state it leaves checked.
- **A launch test for each tab.** A UI test that opens each destination on mock data and checks its page's title
  comes on screen.
- **A mock server when you need one.** When `mocks` has written none, a server that answers every endpoint from the
  client package's preview values, a page at a time, fails or answers late when the scenario says so, and keeps every
  request.
- **A person's data left alone.** Persisted stores are keyed apart for tests and mock launches, so a test never reads
  or writes what a person saved, and the app shows no page while it hosts its unit tests, so no page races the tests
  through the live client.

## How it works

- It reads the app as `granite` and `network` write one: each service's state, work and Ops, each client's endpoints
  and paging, each page's actions, and the destinations. Every expectation that can be read off the code is taken
  from it.
- Craft's model is asked only what a page action leaves when its code does not say: at most three conditions, each
  verified against the services' real fields and parsed before it is kept, and one that never comes right is left out
  with a note.
- Work a test cannot reach (it sends through something a test cannot assign, or reaches the network itself) is left
  out with a note saying what would open it.
- Every file is parsed before any lands, and a file at a path it writes that it did not write is refused, never
  overwritten.

## Works well with

`tests` comes after the other Rao Craft Agents have made an app of [Loom](https://github.com/riteshpakala/Loom)'s
quality: `granite` its services, pages and navigation, `network` its client, and `mocks`, when installed, its
fixtures, which the tests use in place of a server of their own.

## Get it

In Craft, install Tests from the Agent Store, or run
`craft agents add https://github.com/Rao-Craft-Agents/TestsAgent.git`, then say `$tests` in a request.

## Requirements

- A Mac on macOS 14 or later, with Xcode, and an iOS simulator to run the iOS tests and the launch tests.
- An app built on [Granite](https://github.com/riteshpakala/Granite), its services and pages in the shape `granite`
  writes them.
- The launch tests run on the iOS simulator; the macOS scheme keeps them skipped, since they need an interactive
  session there.
- MIT licensed.

## For developers

What a call takes and answers, every file it writes and edits, and how the tests are made are in the
[reference](Docs/Reference.md), and how it is measured is [TESTING.md](TESTING.md).
