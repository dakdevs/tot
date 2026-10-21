import Foundation
import TotCore

/// A temporary copy of T3's schema loaded with `tests/fixtures/t3-seed.sql`.
struct FixtureDatabase {
  let path: String
  let writer: SQLiteDatabase

  static let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

  init() throws {
    path =
      FileManager.default.temporaryDirectory
      .appending(path: "tot-fixture-\(UUID().uuidString).sqlite").path
    writer = try SQLiteDatabase(path: path, readOnly: false)
    try writer.execute("PRAGMA journal_mode=WAL")
    for name in ["t3-schema.sql", "t3-seed.sql"] {
      try writer.execute(String(contentsOf: Self.fixtures.appending(path: name), encoding: .utf8))
    }
  }

  func reader() throws -> T3Database { try T3Database(path: path) }

  /// Simulates T3 starting a new run on a thread.
  func startRun(thread: String, ordinal: Int, userText: String) throws {
    try writer.execute(
      """
      INSERT INTO orchestration_v2_projection_runs (run_id, thread_id, ordinal, provider, status, requested_at, payload_json)
      VALUES ('run-\(thread)-\(ordinal)', '\(thread)', \(ordinal), 'codex', 'running', '2026-10-21T08:00:00.000Z', '{}');
      INSERT INTO orchestration_v2_projection_turn_items (turn_item_id, thread_id, run_id, ordinal, type, status, updated_at, payload_json)
      VALUES ('\(thread)-\(ordinal)-user', '\(thread)', 'run-\(thread)-\(ordinal)', 1, 'user_message', 'completed', '2026-10-21T08:00:00.000Z', '{"text":"\(userText)"}');
      """)
  }

  func completeRun(thread: String, ordinal: Int, reply: String) throws {
    try writer.execute(
      """
      INSERT INTO orchestration_v2_projection_turn_items (turn_item_id, thread_id, run_id, ordinal, type, status, updated_at, payload_json)
      VALUES ('\(thread)-\(ordinal)-agent', '\(thread)', 'run-\(thread)-\(ordinal)', 2, 'assistant_message', 'completed', '2026-10-21T08:05:00.000Z', '{"text":"\(reply)","streaming":false}');
      UPDATE orchestration_v2_projection_runs SET status = 'completed', completed_at = '2026-10-21T08:05:00.000Z'
      WHERE run_id = 'run-\(thread)-\(ordinal)';
      """)
  }
}
