import AppKit
import SwiftUI
import TotCore

@main
struct TotApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate

  var body: some Scene {
    Settings {
      SettingsView(settings: delegate.settings, updates: delegate.updates)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings = AppSettings(defaults: AppDelegate.defaults)
  let updates = UpdateController()
  private var panel: OverlayPanelController?
  private var model: OverlayModel?
  private var pollTask: Task<Void, Never>?
  private var selectionTask: Task<Void, Never>?

  private static func summarizer(for selection: ProviderSelection) -> Summarizer? {
    selection.kind == .off || selection.model.isEmpty ? nil : Summarizer(selection: selection)
  }

  static let defaults =
    ProcessInfo.processInfo.environment["TOT_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:))
    ?? .standard

  func applicationDidFinishLaunching(_ notification: Notification) {
    let environment = ProcessInfo.processInfo.environment
    // UI tests point Tot at a fixture database and isolate its cleared state.
    let databasePath = environment["TOT_DATABASE_PATH"] ?? T3Database.defaultPath
    let clearedURL = environment["TOT_CLEARED_PATH"].map(URL.init(fileURLWithPath:))
    let defaults = Self.defaults
    updates.start()

    let model: OverlayModel
    do {
      model = OverlayModel(
        source: try T3Database(path: databasePath),
        cleared: ClearedCompletions(fileURL: clearedURL ?? ClearedCompletions.defaultURL),
        defaults: defaults)
    } catch {
      model = OverlayModel(
        source: nil, cleared: ClearedCompletions(fileURL: nil),
        sourceError: "T3 Code data not found: \(error)")
    }
    model.refresh(force: true)
    self.model = model
    model.summarizer = Self.summarizer(for: settings.selection)
    // Debounced so typing a custom model ID doesn't start a provider call per keystroke.
    settings.onSelectionChange = { [weak self, weak model] selection in
      self?.selectionTask?.cancel()
      self?.selectionTask = Task {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        model?.summarizer = Self.summarizer(for: selection)
      }
    }
    panel = OverlayPanelController(model: model, settings: settings)
    panel?.show()

    pollTask = Task { [weak model] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        model?.refresh()
      }
    }
  }
}
