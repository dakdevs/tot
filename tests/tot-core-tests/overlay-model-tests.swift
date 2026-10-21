import Foundation
import Testing
import TotCore

@MainActor
struct OverlayModelTests {
  let fixture: FixtureDatabase
  let clearedURL: URL
  let model: OverlayModel

  init() throws {
    fixture = try FixtureDatabase()
    clearedURL = FileManager.default.temporaryDirectory.appending(path: "tot-cleared-\(UUID().uuidString).json")
    model = OverlayModel(source: try fixture.reader(), cleared: ClearedCompletions(fileURL: clearedURL))
    model.refresh(force: true)
  }

  @Test func `lists working threads and counts done ones`() {
    #expect(model.listed.map(\.title) == ["Refactor parser", "Await subagent"])
    #expect(model.listed.map(\.isWaiting) == [false, true])
    #expect(model.done.map(\.title) == ["Fix login redirect", "Resume after settle", "Update docs"])
  }

  @Test func `the done count toggles the finished list`() {
    model.toggleDone()
    #expect(model.showsDone)
    #expect(model.listed.map(\.title) == ["Fix login redirect", "Resume after settle", "Update docs"])
    model.toggleDone()
    #expect(model.listed.map(\.title) == ["Refactor parser", "Await subagent"])
  }

  @Test func `the finished list closes once the last finished thread is cleared`() {
    model.toggleDone()
    for thread in model.done { model.clear(thread) }
    #expect(!model.showsDone)
    #expect(model.listed.map(\.title) == ["Refactor parser", "Await subagent"])
    model.toggleDone()
    #expect(!model.showsDone, "Nothing finished to show")
  }

  @Test func `a selected working thread keeps updating and becomes clearable when it finishes`() throws {
    model.select(try #require(model.working.first { $0.id == "thread-parser" }))
    #expect(model.isReceiving)
    #expect(!model.canClearSelected)

    try fixture.writer.execute(
      """
      UPDATE orchestration_v2_projection_turn_items SET status = 'completed' WHERE turn_item_id = 'parser-1-cmd';
      INSERT INTO orchestration_v2_projection_turn_items (turn_item_id, thread_id, run_id, ordinal, type, status, updated_at, payload_json)
      VALUES ('parser-1-agent', 'thread-parser', 'run-parser-1', 3, 'assistant_message', 'completed', '2026-10-21T08:05:00.000Z', '{"text":"Parser refactored"}');
      UPDATE orchestration_v2_projection_runs SET status = 'completed', completed_at = '2026-10-21T08:05:00.000Z' WHERE run_id = 'run-parser-1';
      """)
    model.refresh()
    #expect(model.selected?.isWorking == false)
    #expect(!model.isReceiving)
    #expect(model.canClearSelected)
    #expect(model.turns.last?.entries.last?.text == "Parser refactored")
    #expect(!model.working.map(\.id).contains("thread-parser"))
    #expect(model.done.first?.id == "thread-parser")
  }

  @Test func `selecting a thread loads its last three turns`() throws {
    model.select(try #require(model.done.first))
    #expect(model.turns.map(\.ordinal) == [2, 3, 4])
    #expect(!model.isReceiving)
    #expect(model.canClearSelected)
  }

  @Test func `clicking a message toggles it between collapsed and expanded`() {
    model.toggle("login-4-agent")
    #expect(model.expanded == ["login-4-agent"])
    model.toggle("login-4-agent")
    #expect(model.expanded.isEmpty)
  }

  @Test func `clearing removes the thread and persists across launches`() throws {
    model.select(try #require(model.done.first))
    model.clearSelected()
    #expect(model.selected == nil)
    #expect(!model.done.map(\.id).contains("thread-login"))

    let relaunched = OverlayModel(source: try fixture.reader(), cleared: ClearedCompletions(fileURL: clearedURL))
    relaunched.refresh(force: true)
    #expect(relaunched.done.map(\.id) == ["thread-resumed", "thread-docs"])
  }

  @Test func `a later completion of a cleared thread shows again`() throws {
    model.select(try #require(model.done.first))
    model.clearSelected()

    try fixture.startRun(thread: "thread-login", ordinal: 5, userText: "One more fix")
    model.refresh()
    #expect(!model.done.map(\.id).contains("thread-login"))
    #expect(model.working.map(\.id).contains("thread-login"))

    try fixture.completeRun(thread: "thread-login", ordinal: 5, reply: "Done again")
    model.refresh()
    #expect(model.done.first?.id == "thread-login")
  }

  @Test func `new turns push the oldest out while the selected thread is receiving`() throws {
    model.select(try #require(model.done.first))
    try fixture.startRun(thread: "thread-login", ordinal: 5, userText: "Follow-up")
    model.refresh()
    #expect(model.turns.map(\.ordinal) == [3, 4, 5])
    #expect(model.isReceiving)
    #expect(!model.canClearSelected)

    try fixture.completeRun(thread: "thread-login", ordinal: 5, reply: "Follow-up done")
    model.refresh()
    #expect(!model.isReceiving)
    #expect(model.turns.last?.entries.map(\.text) == ["Follow-up", "Follow-up done"])
  }

  @Test func `a missing T3 database is reported rather than shown as empty success`() {
    let missing = OverlayModel(
      source: nil, cleared: ClearedCompletions(fileURL: nil), sourceError: "T3 Code data not found")
    missing.refresh(force: true)
    #expect(missing.errorMessage == "T3 Code data not found")
    #expect(missing.done.isEmpty)
  }
}
