import AppKit
import Observation
import Sparkle

/// Owns Sparkle's standard updater. Scheduled checks run hourly and ask Install / Remind Me Later in
/// Sparkle's standard alert; nothing installs without the user choosing it (`SUAutomaticallyUpdate` is off).
@MainActor
@Observable
final class UpdateController: NSObject {
  enum Status: Equatable {
    case idle
    case checking
    case upToDate
    case available(String)
    case failed(String)
  }

  private(set) var status = Status.idle
  private(set) var canCheck = false
  private(set) var lastChecked: Date?
  var automaticallyChecks: Bool {
    get {
      access(keyPath: \.automaticallyChecks)
      return updater?.automaticallyChecksForUpdates ?? false
    }
    set {
      withMutation(keyPath: \.automaticallyChecks) { updater?.automaticallyChecksForUpdates = newValue }
    }
  }

  let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

  @ObservationIgnored private var controller: SPUStandardUpdaterController!
  @ObservationIgnored private var observation: NSKeyValueObservation?
  private var updater: SPUUpdater? { controller?.updater }

  override init() {
    super.init()
    controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
  }

  func start() {
    guard let updater else { return }
    do {
      try updater.start()
    } catch {
      status = .failed(error.localizedDescription)
    }
    lastChecked = updater.lastUpdateCheckDate
    observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
      MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
    }
  }

  /// User-initiated: shows Sparkle's progress, "up to date", error, or update alert, even for a skipped version.
  func checkForUpdates() {
    status = .checking
    NSApp.activate()
    controller.checkForUpdates(nil)
  }
}

// Sparkle calls both delegates on the main thread.
extension UpdateController: @MainActor SPUUpdaterDelegate {
  /// UI tests point Tot at a local fixture feed. Archives are still verified against the embedded EdDSA key.
  func feedURLString(for updater: SPUUpdater) -> String? {
    ProcessInfo.processInfo.environment["TOT_UPDATE_FEED_URL"]
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    status = .available(item.displayVersionString)
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
    status = .upToDate
  }

  func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
    lastChecked = updater.lastUpdateCheckDate
    if let error = error as NSError?, !Self.isBenign(error) {
      status = .failed(error.localizedDescription)
    } else if status == .checking {
      // Cancelled, or a cycle that ended without a verdict.
      status = .idle
    }
  }

  /// "No update" and user cancellation end a cycle with an error but aren't failures.
  private static func isBenign(_ error: NSError) -> Bool {
    error.domain == SUSparkleErrorDomain
      && [SUError.noUpdateError, .installationCanceledError].contains { Int($0.rawValue) == error.code }
  }
}

extension UpdateController: @MainActor SPUStandardUserDriverDelegate {
  var supportsGentleScheduledUpdateReminders: Bool { true }

  /// Tot is an accessory app, so Sparkle would otherwise place a scheduled alert behind other windows.
  /// Becoming a regular app for the session puts the alert in front and in the app switcher.
  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
  ) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
  }

  func standardUserDriverWillFinishUpdateSession() {
    NSApp.setActivationPolicy(.accessory)
  }
}
