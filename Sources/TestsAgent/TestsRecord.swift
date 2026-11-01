import GraniteAgents

/// The tests agent's place in Granite's roster: an app that links this package finds the `tests` agent by this
/// record, with nothing listed by hand.
@used @section("__DATA_CONST,__granite")
let testsRecord: GraniteRoster.Record = { GraniteRoster.record(TestsAgent.self) }
