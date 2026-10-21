import XCTest

/// Drives the real overlay panel against a fixture copy of T3's schema, then mutates the fixture the
/// way the T3 server would while the app is running.
final class OverlayUITests: XCTestCase {
  private var databasePath = ""
  private var app: XCUIApplication!

  private static let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appending(path: "tests/fixtures")

  override func setUpWithError() throws {
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appending(path: "tot-ui-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    databasePath = directory.appending(path: "statev2.sqlite").path
    try sqlite("PRAGMA journal_mode=WAL;")
    for name in ["t3-schema.sql", "t3-seed.sql"] {
      try sqlite(String(contentsOf: Self.fixtures.appending(path: name), encoding: .utf8))
    }
    app = XCUIApplication()
    app.launchEnvironment = [
      "TOT_DATABASE_PATH": databasePath,
      "TOT_CLEARED_PATH": directory.appending(path: "cleared.json").path,
      "TOT_DEFAULTS_SUITE": "dev.dak.tot.ui-tests.\(UUID().uuidString)",
    ]
    // Keeps the overlay tests offline; UpdateUITests covers the updater.
    app.launchArguments = ["-SUEnableAutomaticChecks", "NO"]
    app.launch()
  }

  override func tearDown() {
    app?.terminate()
  }

  func testWorkingThreadsListWithDoneCount() throws {
    let rows = app.buttons.matching(identifier: "thread-row")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(rows.count, 2)
    XCTAssertEqual(rows["Refactor parser"].value as? String, "Running")
    XCTAssertEqual(rows["Await subagent"].value as? String, "Waiting")
    XCTAssertTrue(app.staticTexts["2 working"].exists)
    let doneToggle = app.buttons["done-toggle"]
    XCTAssertEqual(doneToggle.label, "3 done")
    XCTAssertEqual(doneToggle.value as? String, "Hidden")
    attach("working")

    doneToggle.click()
    XCTAssertTrue(rows["Fix login redirect"].waitForExistence(timeout: 5))
    XCTAssertEqual(
      Set(rows.allElementsBoundByIndex.map(\.label)), ["Fix login redirect", "Resume after settle", "Update docs"])
    XCTAssertEqual(rows["Update docs"].value as? String, "Failed")
    XCTAssertEqual(doneToggle.value as? String, "Shown")
    attach("done")

    doneToggle.click()
    XCTAssertTrue(rows["Refactor parser"].waitForExistence(timeout: 5))
    XCTAssertEqual(rows.count, 2)
  }

  func testSelectedWorkingThreadFinishesInPlace() throws {
    let rows = app.buttons.matching(identifier: "thread-row")
    XCTAssertTrue(rows["Refactor parser"].waitForExistence(timeout: 10))
    rows["Refactor parser"].click()
    XCTAssertTrue(app.activityIndicators["Receiving messages"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Clear thread"].exists, "A working thread cannot be cleared")

    try sqlite(
      """
      UPDATE orchestration_v2_projection_turn_items SET status = 'completed' WHERE turn_item_id = 'parser-1-cmd';
      INSERT INTO orchestration_v2_projection_turn_items (turn_item_id, thread_id, run_id, ordinal, type, status, updated_at, payload_json)
      VALUES ('parser-1-agent', 'thread-parser', 'run-parser-1', 3, 'assistant_message', 'completed', '2026-10-21T08:05:00.000Z', '{"text":"Parser refactored."}');
      UPDATE orchestration_v2_projection_runs SET status = 'completed', completed_at = '2026-10-21T08:05:00.000Z' WHERE run_id = 'run-parser-1';
      """)
    XCTAssertTrue(
      app.buttons.matching(identifier: "turn-entry")["Agent: Parser refactored."].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForAbsence(app.activityIndicators["Receiving messages"]))
    XCTAssertTrue(app.buttons["Clear thread"].exists)

    app.buttons["Back to list"].click()
    XCTAssertTrue(rows["Await subagent"].waitForExistence(timeout: 5))
    XCTAssertEqual(rows.count, 1)
    XCTAssertTrue(app.staticTexts["1 working"].exists)
    XCTAssertEqual(app.buttons["done-toggle"].label, "4 done")
  }

  func testDoneThreadsMorphIntoTurnsAndClear() throws {
    let rows = app.buttons.matching(identifier: "thread-row")
    XCTAssertTrue(app.buttons["done-toggle"].waitForExistence(timeout: 10))
    app.buttons["done-toggle"].click()
    XCTAssertTrue(rows["Fix login redirect"].waitForExistence(timeout: 5))

    rows["Fix login redirect"].click()
    let entries = app.buttons.matching(identifier: "turn-entry")
    // Multi-line labels can't be subscript identifiers, so match by prefix.
    let reply = entries.matching(NSPredicate(format: "label BEGINSWITH %@", "Agent: Fixed the redirect loop."))
      .firstMatch
    XCTAssertTrue(reply.waitForExistence(timeout: 5))
    // Last three turns only: run 1 is gone, runs 2–4 are grouped with their continuations.
    XCTAssertFalse(entries["You: Turn one request"].exists)
    XCTAssertTrue(entries["You: Turn two request"].exists)
    XCTAssertEqual(
      entries.matching(NSPredicate(format: "label BEGINSWITH 'Tools:'")).firstMatch.label,
      "Tools: 3 tool calls\nRead auth.ts\n$ bun test auth\nEdited auth.ts")
    XCTAssertTrue(app.buttons["Back to list"].exists)
    XCTAssertTrue(app.buttons["Open in T3 Code"].exists)
    attach("detail")

    let collapsedHeight = reply.frame.height
    XCTAssertEqual(reply.value as? String, "Collapsed")
    reply.click()
    XCTAssertEqual(reply.value as? String, "Expanded")
    XCTAssertGreaterThan(reply.frame.height, collapsedHeight)
    attach("expanded")
    reply.click()
    XCTAssertEqual(reply.value as? String, "Collapsed")

    // T3 starts a new run: the oldest turn leaves, the new input arrives, and the spinner shows.
    try sqlite(
      """
      INSERT INTO orchestration_v2_projection_runs (run_id, thread_id, ordinal, provider, status, requested_at, payload_json)
      VALUES ('run-login-5', 'thread-login', 5, 'codex', 'running', '2026-10-21T08:00:00.000Z', '{}');
      INSERT INTO orchestration_v2_projection_turn_items (turn_item_id, thread_id, run_id, ordinal, type, status, updated_at, payload_json)
      VALUES ('login-5-user', 'thread-login', 'run-login-5', 1, 'user_message', 'completed', '2026-10-21T08:00:00.000Z', '{"text":"Also handle expired tokens"}');
      """)
    XCTAssertTrue(entries["You: Also handle expired tokens"].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForAbsence(entries["You: Turn two request"]))
    XCTAssertTrue(app.activityIndicators["Receiving messages"].exists)
    XCTAssertFalse(app.buttons["Clear thread"].exists, "A working thread cannot be cleared")
    attach("receiving")

    try sqlite(
      """
      INSERT INTO orchestration_v2_projection_turn_items (turn_item_id, thread_id, run_id, ordinal, type, status, updated_at, payload_json)
      VALUES ('login-5-agent', 'thread-login', 'run-login-5', 2, 'assistant_message', 'completed', '2026-10-21T08:05:00.000Z', '{"text":"Expired tokens now refresh.","streaming":false}');
      UPDATE orchestration_v2_projection_runs SET status = 'completed', completed_at = '2026-10-21T08:05:00.000Z' WHERE run_id = 'run-login-5';
      """)
    XCTAssertTrue(entries["Agent: Expired tokens now refresh."].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForAbsence(app.activityIndicators["Receiving messages"]))

    app.buttons["Clear thread"].click()
    XCTAssertTrue(waitForAbsence(rows["Fix login redirect"]))
    XCTAssertEqual(Set(rows.allElementsBoundByIndex.map(\.label)), ["Resume after settle", "Update docs"])
    XCTAssertEqual(app.buttons["done-toggle"].label, "2 done")
    attach("cleared")
  }

  func testBackReturnsToTheList() throws {
    let rows = app.buttons.matching(identifier: "thread-row")
    XCTAssertTrue(app.buttons["done-toggle"].waitForExistence(timeout: 10))
    app.buttons["done-toggle"].click()
    XCTAssertTrue(rows["Update docs"].waitForExistence(timeout: 5))
    rows["Update docs"].click()
    XCTAssertTrue(
      app.buttons.matching(identifier: "turn-entry")["Error: Usage limit reached"].waitForExistence(timeout: 5))
    app.buttons["Back to list"].click()
    XCTAssertTrue(rows["Update docs"].waitForExistence(timeout: 5))
    XCTAssertEqual(rows.count, 3, "Going back returns to the finished list without clearing")
  }

  func testHoverAndSettings() throws {
    let rows = app.buttons.matching(identifier: "thread-row")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
    // Opacity isn't exposed to accessibility; these screenshots are the visual record of idle vs hover.
    rows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: -300, dy: 0)).hover()
    attach("idle")
    rows.firstMatch.hover()
    attach("hover")

    app.buttons["Settings"].click()
    XCTAssertTrue(app.windows.containing(.popUpButton, identifier: nil).firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.popUpButtons.firstMatch.exists, "Provider picker is shown")
    attach("settings")
  }

  private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  private func attach(_ name: String) {
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }

  private func sqlite(_ sql: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [databasePath]
    let input = Pipe()
    process.standardInput = input
    try process.run()
    input.fileHandleForWriting.write(Data(sql.utf8))
    try input.fileHandleForWriting.close()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, "sqlite3 failed")
  }
}
