import Foundation
import Testing
import TotCore

struct T3DatabaseTests {
  let fixture: FixtureDatabase
  let database: T3Database

  init() throws {
    fixture = try FixtureDatabase()
    database = try fixture.reader()
  }

  @Test func `lists top-level unarchived threads with their latest run`() throws {
    let threads = try database.threads()
    #expect(
      Set(threads.map(\.id)) == [
        "thread-login", "thread-notes", "thread-parser", "thread-docs", "thread-resumed", "thread-waiting",
      ])
    let login = try #require(threads.first { $0.id == "thread-login" })
    #expect(login.latestRun.id == "run-login-4")
    #expect(login.latestRun.phase == .completed)
    #expect(login.projectName == "tot")
  }

  @Test func `only finished, unsettled threads count as done`() throws {
    let done = OverlayFilter.doneThreads(try database.threads(), cleared: ClearedCompletions(fileURL: nil))
    // Newest completion first; "notes" was settled after it finished and "parser" is still running.
    #expect(done.map(\.id) == ["thread-login", "thread-resumed", "thread-docs"])
    #expect(done.last?.latestRun.phase == .failed)
  }

  @Test func `working threads report their latest activity`() throws {
    let parser = try #require(try database.threads().first { $0.id == "thread-parser" })
    #expect(parser.latestRun.phase == .working)
    #expect(parser.activity == "$ swift test")
  }

  @Test func `a finished run with a running subagent is still working, as in T3`() throws {
    let threads = try database.threads()
    let waiting = try #require(threads.first { $0.id == "thread-waiting" })
    #expect(waiting.latestRun.phase == .completed)
    #expect(waiting.isWorking)
    #expect(waiting.activity == "Waiting on background work")
    let done = OverlayFilter.doneThreads(threads, cleared: ClearedCompletions(fileURL: nil))
    #expect(!done.map(\.id).contains("thread-waiting"))
  }

  @Test func `recent turns are the last three runs, oldest first`() throws {
    let turns = try database.recentTurns(threadId: "thread-login", limit: 3)
    #expect(turns.map(\.ordinal) == [2, 3, 4])
    #expect(turns[0].entries.map(\.text) == ["Turn two request", "Turn two reply"])
    // Reasoning is never shown.
    #expect(turns[1].entries.map(\.text) == ["Turn three request", "Turn three reply"])
  }

  @Test func `a turn groups the user input with its tool and assistant continuations`() throws {
    let turn = try #require(try database.recentTurns(threadId: "thread-login", limit: 1).first)
    #expect(turn.entries.map(\.kind) == [.user, .tools, .assistant])
    #expect(turn.entries[0].text == "Fix the login redirect loop")
    // Nested child items are excluded; only top-level calls are counted.
    #expect(turn.entries[1].text == "3 tool calls\nRead auth.ts\n$ bun test auth\nEdited auth.ts")
    #expect(turn.entries[2].text.hasPrefix("Fixed the redirect loop."))
  }

  @Test func `failed runs surface their error`() throws {
    let turn = try #require(try database.recentTurns(threadId: "thread-docs", limit: 1).first)
    #expect(turn.phase == .failed)
    #expect(turn.entries.last == TurnEntry(id: "docs-1-error", kind: .error, text: "Usage limit reached"))
  }

  @Test func `data version changes when T3 commits`() throws {
    let before = try database.dataVersion()
    #expect(try database.dataVersion() == before)
    try fixture.startRun(thread: "thread-login", ordinal: 5, userText: "Another request")
    #expect(try database.dataVersion() != before)
  }

  @Test func `the reader never writes`() throws {
    #expect(throws: SQLiteError.self) {
      try SQLiteDatabase(path: fixture.path).execute("DELETE FROM orchestration_v2_projection_runs")
    }
  }
}
