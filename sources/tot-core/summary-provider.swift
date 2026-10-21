import Foundation

/// Which local agent CLI writes one-line thread summaries. Each reuses that CLI's own login, so Tot
/// never reads or stores provider credentials.
public enum ProviderKind: String, Codable, CaseIterable, Sendable {
  case off
  /// The running OpenCode background service, via `opencode api` (as Hex does).
  case openCode
  /// The Codex CLI's ChatGPT subscription login, via `codex exec`.
  case codex
}

/// A model from the provider's live catalog.
public struct ModelOption: Identifiable, Hashable, Codable, Sendable {
  public var id: String
  public var providerID: String?
  public var name: String
  /// OpenCode variants (`none`, `low`, …) or Codex reasoning efforts.
  public var variants: [String]
  /// Codex service tiers such as `priority` ("Fast"); empty for OpenCode, whose fast models are
  /// separate catalog entries.
  public var tiers: [String]

  public init(id: String, providerID: String?, name: String, variants: [String], tiers: [String] = []) {
    self.id = id
    self.providerID = providerID
    self.name = name
    self.variants = variants
    self.tiers = tiers
  }
}

public struct ProviderSelection: Codable, Equatable, Sendable {
  public var kind: ProviderKind
  /// OpenCode `providerID/id` or Codex slug; may be a custom ID absent from the catalog.
  public var model: String
  public var variant: String?
  public var serviceTier: String?

  public init(kind: ProviderKind, model: String = "", variant: String? = nil, serviceTier: String? = nil) {
    self.kind = kind
    self.model = model
    self.variant = variant
    self.serviceTier = serviceTier
  }

  public static let off = ProviderSelection(kind: .off)
}

public struct CLIInvocation: Equatable, Sendable {
  public var executable: String
  public var arguments: [String]
  public var standardInput: String?
}

public enum ProviderCatalog {
  public static func invocation(for kind: ProviderKind) -> CLIInvocation? {
    switch kind {
    case .off: nil
    case .openCode: CLIInvocation(executable: "opencode", arguments: ["api", "get", "/api/model"])
    case .codex: CLIInvocation(executable: "codex", arguments: ["debug", "models"])
    }
  }

  /// Parses `GET /api/model`: enabled models that emit text, keeping catalog `id` (not upstream
  /// `modelID`) because that is what `generate` accepts.
  public static func parseOpenCode(_ data: Data) throws -> [ModelOption] {
    struct Response: Decodable {
      struct Model: Decodable {
        struct Capabilities: Decodable { var output: [String]? }
        struct Variant: Decodable { var id: String }
        var id: String
        var providerID: String
        var name: String?
        var enabled: Bool?
        var capabilities: Capabilities?
        var variants: [Variant]?
      }
      var data: [Model]
    }
    return try JSONDecoder().decode(Response.self, from: data).data
      .filter { $0.enabled != false && ($0.capabilities?.output ?? ["text"]).contains("text") }
      .map {
        ModelOption(
          id: "\($0.providerID)/\($0.id)", providerID: $0.providerID, name: $0.name ?? $0.id,
          variants: $0.variants?.map(\.id) ?? [])
      }
  }

  /// Parses `codex debug models`, keeping models Codex lists in its own picker.
  public static func parseCodex(_ data: Data) throws -> [ModelOption] {
    struct Response: Decodable {
      struct Model: Decodable {
        struct Effort: Decodable { var effort: String }
        struct Tier: Decodable { var id: String }
        var slug: String
        var display_name: String?
        var visibility: String?
        var supported_reasoning_levels: [Effort]?
        var service_tiers: [Tier]?
      }
      var models: [Model]
    }
    return try JSONDecoder().decode(Response.self, from: data).models
      .filter { $0.visibility != "hide" }
      .map {
        ModelOption(
          id: $0.slug, providerID: nil, name: $0.display_name ?? $0.slug,
          variants: $0.supported_reasoning_levels?.map(\.effort) ?? [],
          tiers: $0.service_tiers?.map(\.id) ?? [])
      }
  }
}

public enum SummaryRequest {
  public static func prompt(title: String, turn: Turn) -> String {
    let transcript = turn.entries.map { entry in
      let speaker =
        switch entry.kind {
        case .user: "User"
        case .assistant: "Agent"
        case .tools: "Tools"
        case .error: "Error"
        }
      return "\(speaker): \(entry.text)"
    }.joined(separator: "\n")
    return """
      Summarize what this coding agent did in its latest turn and the outcome, in one plain line of \
      at most 14 words. No preamble, no quotes.
      Thread: \(title)
      \(String(transcript.suffix(6_000)))
      """
  }

  /// Builds the CLI call for one summary. `outputFile` receives Codex's last message.
  public static func invocation(
    for selection: ProviderSelection, prompt: String, outputFile: String
  ) throws -> CLIInvocation? {
    switch selection.kind {
    case .off:
      return nil
    case .openCode:
      // `opencode api` accepts a body only as an argument; it handles server discovery and auth.
      let parts = selection.model.split(separator: "/", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { return nil }
      var model = ["providerID": parts[0], "id": parts[1]]
      model["variant"] = selection.variant
      let body = try JSONSerialization.data(
        withJSONObject: ["prompt": prompt, "model": model], options: [.sortedKeys])
      return CLIInvocation(
        executable: "opencode",
        arguments: ["api", "post", "/api/experimental/generate", "-d", String(decoding: body, as: UTF8.self)])
    case .codex:
      var arguments = [
        "exec", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "-s", "read-only",
        "-m", selection.model, "-o", outputFile,
      ]
      if let variant = selection.variant { arguments += ["-c", "model_reasoning_effort=\(variant)"] }
      if let tier = selection.serviceTier { arguments += ["-c", "service_tier=\(tier)"] }
      // With no prompt argument, `codex exec` reads instructions from stdin.
      return CLIInvocation(executable: "codex", arguments: arguments, standardInput: prompt)
    }
  }

  /// Extracts the summary from `generate`'s `{"data":{"text":…}}` response.
  public static func parseOpenCodeResponse(_ data: Data) -> String? {
    struct Response: Decodable {
      struct Payload: Decodable { var text: String }
      var data: Payload
    }
    return (try? JSONDecoder().decode(Response.self, from: data)).flatMap { clean($0.data.text) }
  }

  public static func clean(_ text: String) -> String? {
    let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
      .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"")))
    return line?.isEmpty == false ? line : nil
  }
}
