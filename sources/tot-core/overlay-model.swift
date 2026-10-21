import Foundation
import Observation

public protocol ThreadSource {
  func dataVersion() throws -> String
  func threads() throws -> [AgentThread]
  func recentTurns(threadId: String, limit: Int) throws -> [Turn]
}

extension T3Database: ThreadSource {}

/// Writes a one-line summary of a thread's latest turn through the selected provider CLI.
public struct Summarizer: Sendable {
  public var selection: ProviderSelection

  public init(selection: ProviderSelection) { self.selection = selection }

  public func summarize(title: String, turn: Turn) async throws -> String? {
    let outputFile = FileManager.default.temporaryDirectory
      .appending(path: "tot-summary-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: outputFile) }
    guard
      let invocation = try SummaryRequest.invocation(
        for: selection, prompt: SummaryRequest.prompt(title: title, turn: turn),
        outputFile: outputFile.path)
    else { return nil }
    let stdout = try await CLIRunner.run(invocation)
    switch selection.kind {
    case .off: return nil
    case .openCode: return SummaryRequest.parseOpenCodeResponse(stdout)
    case .codex: return SummaryRequest.clean((try? String(contentsOf: outputFile, encoding: .utf8)) ?? "")
    }
  }
}

@MainActor
@Observable
public final class OverlayModel {
  public static let turnLimit = 3

  /// Running or waiting threads — the list the overlay shows by default.
  public private(set) var working: [AgentThread] = []
  /// Finished threads awaiting a look, counted in the status bar and listed while `showsDone` is on.
  public private(set) var done: [AgentThread] = []
  public private(set) var showsDone = false
  public private(set) var selected: AgentThread?
  public private(set) var turns: [Turn] = []
  public private(set) var expanded: Set<String> = []
  public private(set) var errorMessage: String?
  /// One-line summaries keyed by completion, so a new completion gets a fresh summary.
  public private(set) var summaries: [String: String]

  public var summarizer: Summarizer? {
    didSet {
      summaryFailures.removeAll()
      scheduleSummary()
    }
  }

  private let source: (any ThreadSource)?
  private var cleared: ClearedCompletions
  private let defaults: UserDefaults?
  private var lastVersion: String?
  private var summaryTask: Task<Void, Never>?
  private var summaryFailures: Set<String> = []
  private static let summariesKey = "summaries"

  public init(
    source: (any ThreadSource)?, cleared: ClearedCompletions, defaults: UserDefaults? = nil,
    sourceError: String? = nil
  ) {
    self.source = source
    self.cleared = cleared
    self.defaults = defaults
    summaries = defaults?.dictionary(forKey: Self.summariesKey) as? [String: String] ?? [:]
    errorMessage = sourceError
  }

  /// The threads the list shows.
  public var listed: [AgentThread] { showsDone ? done : working }

  /// Switches the list between working and finished threads; there is nothing to switch to while none
  /// are finished.
  public func toggleDone() {
    showsDone = !showsDone && !done.isEmpty
  }

  /// The selected thread is still producing output.
  public var isReceiving: Bool {
    selected?.isWorking == true
      || turns.contains { $0.entries.contains(where: \.isStreaming) }
  }

  public var canClearSelected: Bool {
    guard let thread = selected else { return false }
    return !OverlayFilter.doneThreads([thread], cleared: cleared).isEmpty
  }

  /// Re-reads T3 when its database changed since the last read, or always when `force` is set.
  public func refresh(force: Bool = false) {
    guard let source else { return }
    do {
      let version = try source.dataVersion()
      guard force || version != lastVersion else { return }
      lastVersion = version
      let threads = try source.threads()
      if !threads.isEmpty { try cleared.prune(keeping: threads) }
      done = OverlayFilter.doneThreads(threads, cleared: cleared)
      working = threads.filter(\.isWorking)
      if done.isEmpty { showsDone = false }
      if let id = selected?.id {
        selected = threads.first { $0.id == id } ?? selected
        turns = try source.recentTurns(threadId: id, limit: Self.turnLimit)
      }
      errorMessage = nil
      scheduleSummary()
    } catch {
      errorMessage = String(describing: error)
    }
  }

  public func select(_ thread: AgentThread) {
    selected = thread
    expanded = []
    turns = (try? source?.recentTurns(threadId: thread.id, limit: Self.turnLimit)) ?? []
  }

  public func back() {
    selected = nil
    turns = []
    expanded = []
  }

  /// Hides the selected thread's current completion; a later completion of the thread shows again.
  public func clearSelected() {
    guard canClearSelected, let thread = selected else { return }
    clear(thread)
    back()
  }

  public func clear(_ thread: AgentThread) {
    do {
      try cleared.clear(thread.latestRun)
    } catch {
      errorMessage = "Could not save cleared state: \(error)"
    }
    done.removeAll { $0.id == thread.id }
    if done.isEmpty { showsDone = false }
  }

  public func toggle(_ entryID: String) {
    if expanded.remove(entryID) == nil { expanded.insert(entryID) }
  }

  /// Summarizes done threads one at a time so the overlay never fans out provider calls.
  private func scheduleSummary() {
    guard summaryTask == nil, let summarizer, summarizer.selection.kind != .off, let source,
      let thread = done.first(where: {
        let key = $0.latestRun.completionKey
        return summaries[key] == nil && !summaryFailures.contains(key)
      })
    else { return }
    let key = thread.latestRun.completionKey
    guard let turn = try? source.recentTurns(threadId: thread.id, limit: 1).last else {
      summaryFailures.insert(key)
      return
    }
    summaryTask = Task {
      do {
        if let line = try await summarizer.summarize(title: thread.title, turn: turn) {
          // Keep only summaries for completions still listed, so storage stays bounded.
          let live = Set(done.map(\.latestRun.completionKey))
          summaries = summaries.filter { live.contains($0.key) }
          summaries[key] = line
          defaults?.set(summaries, forKey: Self.summariesKey)
        } else {
          summaryFailures.insert(key)
        }
      } catch {
        summaryFailures.insert(key)
        errorMessage = "Summary failed: \(error)"
      }
      summaryTask = nil
      scheduleSummary()
    }
  }
}
