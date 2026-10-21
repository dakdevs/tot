import Foundation

/// The fields Tot reads from one top-level `orchestration_v2_projection_turn_items` row.
public struct RawTurnItem: Sendable, Equatable {
  public var id: String
  public var type: String
  public var text: String?
  public var title: String?
  public var toolName: String?
  public var input: String?
  public var fileName: String?
  public var failure: String?
  public var isStreaming: Bool

  public init(
    id: String, type: String, text: String? = nil, title: String? = nil, toolName: String? = nil,
    input: String? = nil, fileName: String? = nil, failure: String? = nil, isStreaming: Bool = false
  ) {
    self.id = id
    self.type = type
    self.text = text
    self.title = title
    self.toolName = toolName
    self.input = input
    self.fileName = fileName
    self.failure = failure
    self.isStreaming = isStreaming
  }
}

public enum TurnBuilder {
  static let toolTypes: Set<String> = [
    "command_execution", "dynamic_tool", "file_change", "file_search", "web_search", "subagent",
  ]

  /// Converts a run's ordered items into overlay entries. Consecutive tool calls collapse into one
  /// entry so a turn reads as: what was sent, what the agent did, and what it said.
  public static func entries(from items: [RawTurnItem]) -> [TurnEntry] {
    var entries: [TurnEntry] = []
    var tools: [(id: String, label: String)] = []

    func flushTools() {
      guard let first = tools.first else { return }
      let count = tools.count == 1 ? "1 tool call" : "\(tools.count) tool calls"
      let labels = tools.map(\.label).joined(separator: "\n")
      entries.append(TurnEntry(id: first.id, kind: .tools, text: "\(count)\n\(labels)"))
      tools.removeAll()
    }

    for item in items {
      switch item.type {
      case "user_message", "assistant_message":
        guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { continue }
        flushTools()
        let kind: TurnEntry.Kind = item.type == "user_message" ? .user : .assistant
        entries.append(TurnEntry(id: item.id, kind: kind, text: text, isStreaming: item.isStreaming))
      case "error":
        flushTools()
        entries.append(TurnEntry(id: item.id, kind: .error, text: item.failure ?? item.title ?? "Error"))
      case let type where toolTypes.contains(type):
        tools.append((item.id, toolLabel(item)))
      default:
        continue  // reasoning, checkpoints, notifications, and other bookkeeping
      }
    }
    flushTools()
    return entries
  }

  public static func toolLabel(_ item: RawTurnItem) -> String {
    switch item.type {
    case "command_execution":
      let command = item.input?.split(separator: "\n").first.map(String.init) ?? item.title ?? "command"
      return "$ \(command)"
    case "file_change":
      return "Edited \(item.fileName.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "file")"
    default:
      return item.title ?? item.toolName ?? item.type.replacingOccurrences(of: "_", with: " ")
    }
  }
}
