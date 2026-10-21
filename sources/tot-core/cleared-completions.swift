import Foundation

/// Completions the user cleared from the overlay, persisted as a JSON array of completion keys.
/// Tot never writes to T3; clearing is local to the overlay.
public struct ClearedCompletions {
  public private(set) var keys: Set<String>
  private let fileURL: URL?

  public static var defaultURL: URL {
    URL.applicationSupportDirectory.appending(path: "Tot/cleared-completions.json")
  }

  /// Pass `nil` for an in-memory store.
  public init(fileURL: URL?) {
    self.fileURL = fileURL
    let data = fileURL.flatMap { try? Data(contentsOf: $0) }
    keys = data.flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
  }

  public func contains(_ run: RunSummary) -> Bool { keys.contains(run.completionKey) }

  public mutating func clear(_ run: RunSummary) throws {
    keys.insert(run.completionKey)
    try save()
  }

  /// Drops keys that no longer name any thread's latest run; a later run always gets a new key,
  /// so those keys can never match again.
  public mutating func prune(keeping threads: [AgentThread]) throws {
    let live = Set(threads.map(\.latestRun.completionKey))
    let pruned = keys.intersection(live)
    guard pruned != keys else { return }
    keys = pruned
    try save()
  }

  private func save() throws {
    guard let fileURL else { return }
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(keys.sorted()).write(to: fileURL, options: .atomic)
  }
}

public enum OverlayFilter {
  /// Threads whose latest run finished and still needs a look: not cleared here, not settled in T3
  /// after it finished.
  public static func doneThreads(_ threads: [AgentThread], cleared: ClearedCompletions)
    -> [AgentThread]
  {
    threads.filter { thread in
      let run = thread.latestRun
      guard run.phase == .completed || run.phase == .failed, !thread.hasPendingWork, !cleared.contains(run) else {
        return false
      }
      guard let settledAt = thread.settledAt else { return true }
      // ISO-8601 UTC timestamps order lexicographically.
      return !settledAt.isEmpty && settledAt < (run.completedAt ?? "")
    }
  }
}
