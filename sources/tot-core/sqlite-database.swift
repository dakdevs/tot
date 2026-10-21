import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
  public let description: String
}

/// A minimal SQLite connection. Tot opens T3's database read-only; tests open fixtures read-write.
public final class SQLiteDatabase {
  private var handle: OpaquePointer?

  public init(path: String, readOnly: Bool = true) throws {
    // `mode=ro` (not `immutable=1`) so WAL writes from the running T3 server stay visible.
    let uri = readOnly ? "file:\(path)?mode=ro" : path
    let flags =
      (readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_URI : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
      | SQLITE_OPEN_NOMUTEX
    guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
      sqlite3_close(handle)
      throw SQLiteError(description: "open \(path): \(message)")
    }
    sqlite3_busy_timeout(handle, 2_000)
  }

  deinit { sqlite3_close(handle) }

  public func execute(_ sql: String) throws {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError(sql) }
  }

  /// Runs `sql` with positional text bindings and returns each row's columns as optional strings.
  public func query(_ sql: String, _ bindings: [String] = []) throws -> [[String?]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError(sql) }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, value) in bindings.enumerated() {
      sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
    }
    var rows: [[String?]] = []
    let columns = sqlite3_column_count(statement)
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW:
        rows.append(
          (0..<columns).map { column in
            sqlite3_column_text(statement, column).map { String(cString: $0) }
          })
      case SQLITE_DONE: return rows
      default: throw lastError(sql)
      }
    }
  }

  private func lastError(_ sql: String) -> SQLiteError {
    SQLiteError(description: "\(String(cString: sqlite3_errmsg(handle))) in: \(sql.prefix(80))")
  }
}
