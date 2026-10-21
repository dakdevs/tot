import Foundation

/// The overlay's reading of a T3 run status (`orchestration_v2_projection_runs.status`).
public enum RunPhase: Sendable, Equatable {
  case working, completed, failed, stopped

  public init(status: String) {
    switch status {
    case "completed": self = .completed
    case "failed": self = .failed
    case "interrupted", "cancelled", "rolled_back": self = .stopped
    // queued, preparing, starting, running, waiting — and any status T3 adds later.
    default: self = .working
    }
  }
}

public struct RunSummary: Sendable, Equatable {
  public var id: String
  public var ordinal: Int
  public var phase: RunPhase
  public var completedAt: String?

  public init(id: String, ordinal: Int, phase: RunPhase, completedAt: String?) {
    self.id = id
    self.ordinal = ordinal
    self.phase = phase
    self.completedAt = completedAt
  }

  /// Identifies one completion. A later run of the same thread has a new key, so clearing never hides it.
  public var completionKey: String { "\(id)@\(completedAt ?? "")" }
}

public struct AgentThread: Identifiable, Sendable, Equatable {
  public var id: String
  public var title: String
  public var projectName: String?
  public var latestRun: RunSummary
  /// When the user settled the thread in T3 (`settledOverride == "settled"`); nil while unsettled.
  public var settledAt: String?
  /// A subagent or background tool is still running after the run itself ended (T3 shows "Waiting").
  public var hasPendingWork: Bool
  /// What a working thread is doing now: its latest tool call or assistant line.
  public var activity: String?

  public var isWorking: Bool { latestRun.phase == .working || hasPendingWork }
  /// The run ended but a subagent or background tool hasn't (T3's "Waiting").
  public var isWaiting: Bool { latestRun.phase != .working && hasPendingWork }

  public init(
    id: String, title: String, projectName: String?, latestRun: RunSummary, settledAt: String?,
    hasPendingWork: Bool = false, activity: String? = nil
  ) {
    self.id = id
    self.title = title
    self.projectName = projectName
    self.latestRun = latestRun
    self.settledAt = settledAt
    self.hasPendingWork = hasPendingWork
    self.activity = activity
  }
}

public struct TurnEntry: Identifiable, Sendable, Equatable {
  public enum Kind: Sendable, Equatable { case user, assistant, tools, error }

  public var id: String
  public var kind: Kind
  public var text: String
  public var isStreaming: Bool

  public init(id: String, kind: Kind, text: String, isStreaming: Bool = false) {
    self.id = id
    self.kind = kind
    self.text = text
    self.isStreaming = isStreaming
  }
}

/// One T3 run: a user input together with every assistant and tool continuation it produced.
public struct Turn: Identifiable, Sendable, Equatable {
  public var id: String
  public var ordinal: Int
  public var phase: RunPhase
  public var entries: [TurnEntry]

  public init(id: String, ordinal: Int, phase: RunPhase, entries: [TurnEntry]) {
    self.id = id
    self.ordinal = ordinal
    self.phase = phase
    self.entries = entries
  }
}
