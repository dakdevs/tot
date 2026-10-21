import AppKit
import SwiftUI
import TotCore

struct SettingsView: View {
  @Bindable var settings: AppSettings
  @Bindable var updates: UpdateController
  @State private var catalog: [ModelOption] = []
  @State private var catalogError: String?
  @State private var isLoading = false

  var body: some View {
    Form {
      Section("Overlay") {
        Slider(value: $settings.idleTint, in: OverlayGlass.idleTintRange) {
          Text("Idle glass tint")
        }
        Toggle("Open threads in the browser (web route)", isOn: $settings.openThreadsInBrowser)
        Text(
          "T3 Code's desktop app has no thread deep link, so “Open in T3 Code” brings the app forward. "
            + "The web route opens the exact thread but needs a signed-in browser session."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Thread summaries") {
        Picker("Provider", selection: $settings.selection.kind) {
          Text("Off").tag(ProviderKind.off)
          Text("OpenCode (running service)").tag(ProviderKind.openCode)
          Text("Codex (ChatGPT login)").tag(ProviderKind.codex)
        }
        if settings.selection.kind != .off {
          modelControls
        }
      }
      updateSection
      Section {
        Button("Quit Tot") { NSApp.terminate(nil) }
      }
    }
    .formStyle(.grouped)
    .frame(width: 460)
    .task(id: settings.selection.kind) { await loadCatalog() }
  }

  private var updateSection: some View {
    Section("Updates") {
      Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Version \(updates.currentVersion)")
          updateStatus.font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("update-status")
        }
        Spacer()
        if updates.status == .checking { ProgressView().controlSize(.small) }
        Button("Check for Updates…") { updates.checkForUpdates() }
          .disabled(!updates.canCheck)
      }
    }
  }

  private var updateStatus: Text {
    switch updates.status {
    case .checking: Text("Checking for updates…")
    case .upToDate: Text("Tot is up to date.")
    case .available(let version): Text("Version \(version) is available.")
    case .failed(let message): Text("Update check failed: \(message)").foregroundStyle(.red)
    case .idle:
      if let date = updates.lastChecked {
        Text("Last checked \(date, format: .relative(presentation: .named)).")
      } else {
        Text("Not checked yet.")
      }
    }
  }

  @ViewBuilder private var modelControls: some View {
    let model = catalog.first { $0.id == settings.selection.model }
    Picker("Model", selection: $settings.selection.model) {
      if model == nil { Text(settings.selection.model.isEmpty ? "Choose…" : "Custom").tag(settings.selection.model) }
      ForEach(catalog) { Text("\($0.name) (\($0.id))").tag($0.id) }
    }
    TextField("Model ID", text: $settings.selection.model, prompt: Text("openai/gpt-6-luna-fast"))
    let variants = model?.variants ?? []
    if !variants.isEmpty {
      Picker(settings.selection.kind == .codex ? "Reasoning effort" : "Variant", selection: $settings.selection.variant)
      {
        Text("Default").tag(String?.none)
        ForEach(variants, id: \.self) { Text($0).tag(String?.some($0)) }
      }
    }
    let tiers = model?.tiers ?? []
    if !tiers.isEmpty {
      Picker("Service tier", selection: $settings.selection.serviceTier) {
        Text("Default").tag(String?.none)
        ForEach(tiers, id: \.self) { Text($0 == "priority" ? "Fast (priority)" : $0).tag(String?.some($0)) }
      }
    }
    HStack {
      if isLoading { ProgressView().controlSize(.small) }
      if let catalogError { Text(catalogError).font(.caption).foregroundStyle(.red) }
      Spacer()
      Button("Reload models") { Task { await loadCatalog() } }
    }
  }

  private func loadCatalog() async {
    guard let invocation = ProviderCatalog.invocation(for: settings.selection.kind) else {
      catalog = []
      return
    }
    let kind = settings.selection.kind
    isLoading = true
    defer { isLoading = false }
    do {
      let data = try await CLIRunner.run(invocation, timeout: 30)
      catalog = kind == .openCode ? try ProviderCatalog.parseOpenCode(data) : try ProviderCatalog.parseCodex(data)
      catalogError = nil
    } catch {
      catalog = []
      catalogError = String(describing: error)
    }
  }
}
