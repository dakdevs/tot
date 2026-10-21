import Foundation
import Testing
import TotCore

struct ProviderCatalogTests {
  @Test func `OpenCode catalog keeps enabled text models with their variants`() throws {
    let json = """
      {"data":[
        {"id":"gpt-6-luna-fast","modelID":"gpt-6-luna","providerID":"openai","name":"GPT-6 Luna Fast","enabled":true,
         "capabilities":{"output":["text"]},"variants":[{"id":"none"},{"id":"low"}]},
        {"id":"image-1","providerID":"openai","name":"Image","enabled":true,"capabilities":{"output":["image"]}},
        {"id":"off-model","providerID":"anthropic","name":"Disabled","enabled":false,"capabilities":{"output":["text"]}}
      ],"location":{}}
      """
    let models = try ProviderCatalog.parseOpenCode(Data(json.utf8))
    #expect(
      models == [
        ModelOption(
          id: "openai/gpt-6-luna-fast", providerID: "openai", name: "GPT-6 Luna Fast", variants: ["none", "low"])
      ])
  }

  @Test func `Codex catalog keeps listed models with efforts and tiers`() throws {
    let json = """
      {"models":[
        {"slug":"gpt-6-luna","display_name":"GPT-6-Luna","visibility":"list",
         "supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"}],"service_tiers":[{"id":"priority","name":"Fast"}]},
        {"slug":"gpt-reserve","display_name":"GPT-Reserve","visibility":"hide"}
      ]}
      """
    let models = try ProviderCatalog.parseCodex(Data(json.utf8))
    #expect(
      models == [
        ModelOption(
          id: "gpt-6-luna", providerID: nil, name: "GPT-6-Luna", variants: ["low", "medium"], tiers: ["priority"])
      ])
  }
}

struct SummaryRequestTests {
  let turn = Turn(
    id: "run", ordinal: 1, phase: .completed,
    entries: [
      TurnEntry(id: "u", kind: .user, text: "Fix the bug"),
      TurnEntry(id: "a", kind: .assistant, text: "Fixed it"),
    ])

  @Test func `OpenCode summaries go through generate with the chosen variant`() throws {
    let selection = ProviderSelection(kind: .openCode, model: "openai/gpt-6-luna-fast", variant: "low")
    let invocation = try #require(try SummaryRequest.invocation(for: selection, prompt: "P", outputFile: "/tmp/x"))
    #expect(invocation.executable == "opencode")
    #expect(invocation.arguments.prefix(3) == ["api", "post", "/api/experimental/generate"])
    let body = try JSONSerialization.jsonObject(with: Data(invocation.arguments[4].utf8)) as? NSDictionary
    #expect(body == ["prompt": "P", "model": ["providerID": "openai", "id": "gpt-6-luna-fast", "variant": "low"]])
  }

  @Test func `OpenCode model IDs must name a provider`() throws {
    let selection = ProviderSelection(kind: .openCode, model: "gpt-6-luna-fast")
    #expect(try SummaryRequest.invocation(for: selection, prompt: "P", outputFile: "/tmp/x") == nil)
  }

  @Test func `Codex summaries run ephemerally with effort and tier, prompt on stdin`() throws {
    let selection = ProviderSelection(kind: .codex, model: "gpt-6-luna", variant: "low", serviceTier: "priority")
    let invocation = try #require(try SummaryRequest.invocation(for: selection, prompt: "P", outputFile: "/tmp/out"))
    #expect(invocation.executable == "codex")
    #expect(invocation.standardInput == "P")
    #expect(invocation.arguments.contains("--ephemeral"))
    #expect(invocation.arguments.split(separator: "-m").last?.first == "gpt-6-luna")
    #expect(invocation.arguments.suffix(4) == ["-c", "model_reasoning_effort=low", "-c", "service_tier=priority"])
    #expect(invocation.arguments.contains("/tmp/out"))
  }

  @Test func `prompt includes the turn transcript`() {
    let prompt = SummaryRequest.prompt(title: "Bugfix", turn: turn)
    #expect(prompt.contains("Thread: Bugfix"))
    #expect(prompt.contains("User: Fix the bug\nAgent: Fixed it"))
  }

  @Test func `responses reduce to one clean line`() {
    #expect(
      SummaryRequest.parseOpenCodeResponse(Data(#"{"data":{"text":"\"Fixed login.\"\nextra"}}"#.utf8)) == "Fixed login."
    )
    #expect(SummaryRequest.parseOpenCodeResponse(Data(#"{"error":"nope"}"#.utf8)) == nil)
    #expect(SummaryRequest.clean("  \n") == nil)
  }
}

struct T3LocationsTests {
  @Test func `thread URL uses the server origin, environment, and an encoded thread ID`() throws {
    let userdata = FileManager.default.temporaryDirectory.appending(path: "tot-userdata-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
    try #"{"origin":"http://127.0.0.1:3773","port":3773}"#.write(
      to: userdata.appending(path: "server-runtime.json"), atomically: true, encoding: .utf8)
    try "env-123\n".write(to: userdata.appending(path: "environment-id"), atomically: true, encoding: .utf8)

    let url = T3Locations.threadURL(userdata: userdata, threadID: "thread:delegated%3Ax")
    #expect(url?.absoluteString == "http://127.0.0.1:3773/env-123/thread%3Adelegated%253Ax")
  }

  @Test func `no URL without T3 runtime metadata`() {
    let empty = FileManager.default.temporaryDirectory.appending(path: "tot-missing-\(UUID().uuidString)")
    #expect(T3Locations.threadURL(userdata: empty, threadID: "t") == nil)
  }
}

struct RunPhaseTests {
  @Test(arguments: [
    ("queued", RunPhase.working), ("preparing", .working), ("waiting", .working), ("completed", .completed),
    ("failed", .failed), ("interrupted", .stopped), ("cancelled", .stopped), ("rolled_back", .stopped),
    ("some_future_status", .working),
  ])
  func `maps T3 run statuses`(status: String, phase: RunPhase) {
    #expect(RunPhase(status: status) == phase)
  }
}

/// Calls the real provider CLIs with the user's existing logins. Opt in with TOT_LIVE_PROVIDER_TESTS=1;
/// each call spends a small amount of subscription usage.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TOT_LIVE_PROVIDER_TESTS"] == "1"))
struct LiveProviderTests {
  let turn = Turn(
    id: "run", ordinal: 1, phase: .completed,
    entries: [
      TurnEntry(id: "u", kind: .user, text: "Fix the login redirect loop"),
      TurnEntry(id: "a", kind: .assistant, text: "Moved the session check before the redirect; auth tests pass."),
    ])

  @Test(arguments: [
    ProviderSelection(kind: .openCode, model: "openai/gpt-6-luna-fast", variant: "low"),
    ProviderSelection(kind: .codex, model: "gpt-6-luna", variant: "low", serviceTier: "priority"),
  ])
  func `summarizes through the provider CLI`(selection: ProviderSelection) async throws {
    let line = try #require(try await Summarizer(selection: selection).summarize(title: "Login", turn: turn))
    #expect(!line.isEmpty && !line.contains("\n"))
  }

  @Test(arguments: [ProviderKind.openCode, .codex])
  func `loads the live model catalog`(kind: ProviderKind) async throws {
    let data = try await CLIRunner.run(try #require(ProviderCatalog.invocation(for: kind)))
    let models = kind == .openCode ? try ProviderCatalog.parseOpenCode(data) : try ProviderCatalog.parseCodex(data)
    let expected = kind == .openCode ? "openai/gpt-6-luna-fast" : "gpt-6-luna"
    #expect(models.first { $0.id == expected }?.variants.contains("low") == true)
  }
}
