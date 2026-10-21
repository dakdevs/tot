import Foundation

/// Read-only access to T3 Code's orchestration v2 projections in `userdata/statev2.sqlite`.
public final class T3Database {
  private let db: SQLiteDatabase

  public static var defaultPath: String {
    let home = ProcessInfo.processInfo.environment["T3CODE_HOME"] ?? "\(NSHomeDirectory())/.t3"
    return "\(home)/userdata/statev2.sqlite"
  }

  public init(path: String = T3Database.defaultPath) throws {
    db = try SQLiteDatabase(path: path)
  }

  /// Changes whenever another connection (the T3 server) commits; cheap enough to poll.
  public func dataVersion() throws -> String {
    try db.query("PRAGMA data_version").first?.first.flatMap { $0 } ?? ""
  }

  /// Top-level, unarchived threads with their latest run.
  public func threads() throws -> [AgentThread] {
    let rows = try db.query(
      """
      SELECT t.thread_id, t.title, p.title, r.run_id, r.ordinal, r.status, r.completed_at,
             json_extract(t.payload_json, '$.settledAt'), json_extract(t.payload_json, '$.settledOverride'),
             -- Mirrors T3's shell_pending index: background tools or subagents still running.
             EXISTS (SELECT 1 FROM orchestration_v2_projection_turn_items i
                     WHERE i.thread_id = t.thread_id
                       AND i.type IN ('command_execution', 'dynamic_tool', 'subagent')
                       AND i.status NOT IN ('completed', 'interrupted', 'failed', 'cancelled'))
      FROM orchestration_v2_projection_threads t
      JOIN orchestration_v2_projection_runs r ON r.thread_id = t.thread_id
        AND r.ordinal = (SELECT max(ordinal) FROM orchestration_v2_projection_runs x
                         WHERE x.thread_id = t.thread_id)
      LEFT JOIN projection_projects p ON p.project_id = t.project_id
      WHERE t.archived_at IS NULL AND t.deleted_at IS NULL
        AND json_extract(t.payload_json, '$.lineage.parentThreadId') IS NULL
      ORDER BY coalesce(r.completed_at, r.requested_at) DESC
      """)
    var threads = rows.compactMap { row -> AgentThread? in
      guard let id = row[0], let runId = row[3], let ordinal = row[4].flatMap({ Int($0) }),
        let status = row[5]
      else { return nil }
      return AgentThread(
        id: id, title: row[1] ?? "Untitled", projectName: row[2],
        latestRun: RunSummary(
          id: runId, ordinal: ordinal, phase: RunPhase(status: status), completedAt: row[6]),
        settledAt: row[8] == "settled" ? row[7] ?? "" : nil, hasPendingWork: row[9] == "1")
    }
    for index in threads.indices where threads[index].isWorking {
      threads[index].activity =
        threads[index].latestRun.phase == .working
        ? try activity(runId: threads[index].latestRun.id) : "Waiting on background work"
    }
    return threads
  }

  /// The latest `limit` runs of a thread, oldest first, each grouped into a turn.
  public func recentTurns(threadId: String, limit: Int = 3) throws -> [Turn] {
    let runs = try db.query(
      """
      SELECT run_id, ordinal, status FROM orchestration_v2_projection_runs
      WHERE thread_id = ? ORDER BY ordinal DESC LIMIT \(limit)
      """, [threadId])
    return try runs.reversed().compactMap { row in
      guard let runId = row[0], let ordinal = row[1].flatMap({ Int($0) }), let status = row[2] else {
        return nil
      }
      let items = try turnItems(runId: runId)
      return Turn(
        id: runId, ordinal: ordinal, phase: RunPhase(status: status),
        entries: TurnBuilder.entries(from: items))
    }
  }

  private func turnItems(runId: String, newestFirst: Bool = false, limit: Int = -1) throws
    -> [RawTurnItem]
  {
    // Extract only the needed fields; tool payloads embed full outputs.
    try db.query(
      """
      SELECT turn_item_id, type,
             json_extract(payload_json, '$.text'), json_extract(payload_json, '$.title'),
             json_extract(payload_json, '$.toolName'), json_extract(payload_json, '$.input'),
             json_extract(payload_json, '$.fileName'), json_extract(payload_json, '$.failure.message'),
             json_extract(payload_json, '$.streaming')
      FROM orchestration_v2_projection_turn_items
      WHERE run_id = ? AND parent_item_id IS NULL
        AND type NOT IN ('reasoning', 'checkpoint', 'notification', 'compaction')
      ORDER BY ordinal \(newestFirst ? "DESC" : "ASC") LIMIT \(limit)
      """, [runId]
    ).compactMap { row in
      guard let id = row[0], let type = row[1] else { return nil }
      return RawTurnItem(
        id: id, type: type, text: row[2], title: row[3], toolName: row[4], input: row[5],
        fileName: row[6], failure: row[7], isStreaming: row[8] == "1")
    }
  }

  private func activity(runId: String) throws -> String? {
    guard let item = try turnItems(runId: runId, newestFirst: true, limit: 1).first else {
      return nil
    }
    if TurnBuilder.toolTypes.contains(item.type) { return TurnBuilder.toolLabel(item) }
    return item.text?.split(separator: "\n").first.map(String.init)
  }
}
