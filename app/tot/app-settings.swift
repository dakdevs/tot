import Foundation
import Observation
import TotCore

@MainActor
@Observable
final class AppSettings {
  private let defaults: UserDefaults

  var selection: ProviderSelection {
    didSet {
      defaults.set(try? JSONEncoder().encode(selection), forKey: "providerSelection")
      onSelectionChange?(selection)
    }
  }

  /// Window-colored backing in the glass while the pointer is elsewhere; hovering always fills it.
  var idleTint: Double {
    didSet { defaults.set(idleTint, forKey: "idleTint") }
  }

  /// T3 Code's desktop app has no thread deep link, so opening a specific thread needs the web UI.
  var openThreadsInBrowser: Bool {
    didSet { defaults.set(openThreadsInBrowser, forKey: "openThreadsInBrowser") }
  }

  @ObservationIgnored var onSelectionChange: ((ProviderSelection) -> Void)?

  init(defaults: UserDefaults) {
    self.defaults = defaults
    selection =
      defaults.data(forKey: "providerSelection")
      .flatMap { try? JSONDecoder().decode(ProviderSelection.self, from: $0) } ?? .off
    if let tint = defaults.object(forKey: "idleTint") as? Double {
      idleTint = tint
    } else if let legacy = defaults.object(forKey: "idleOpacity") as? Double {
      let tint = OverlayGlass.idleTint(fromLegacyOpacity: legacy)
      idleTint = tint
      defaults.set(tint, forKey: "idleTint")
      defaults.removeObject(forKey: "idleOpacity")
    } else {
      idleTint = OverlayGlass.defaultIdleTint
    }
    openThreadsInBrowser = defaults.bool(forKey: "openThreadsInBrowser")
  }
}
