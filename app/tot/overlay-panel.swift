import AppKit
import SwiftUI
import TotCore

/// A borderless, non-activating panel: it floats above full-screen video on every Space without
/// taking focus from the app underneath.
final class OverlayPanel: NSPanel {
  init() {
    super.init(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    isFloatingPanel = true
    hidesOnDeactivate = false
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    acceptsMouseMovedEvents = true
    becomesKeyOnlyIfNeeded = true
    setAccessibilityIdentifier("tot-overlay")
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayPanelController {
  static let width: CGFloat = 360
  static let margin: CGFloat = 20

  private let panel = OverlayPanel()
  private var shrinkWork: DispatchWorkItem?
  private var height: CGFloat = 120

  init(model: OverlayModel, settings: AppSettings) {
    let root = OverlayView(model: model, settings: settings) { [weak self] size in
      self?.contentHeightChanged(size.height)
    }
    let hosting = NSHostingView(rootView: root)
    hosting.sizingOptions = []
    panel.contentView = hosting
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.layout() } }
  }

  func show() {
    layout()
    panel.orderFrontRegardless()
  }

  /// Grows immediately so an expanding morph is never clipped; shrinks after the animation settles.
  private func contentHeightChanged(_ newHeight: CGFloat) {
    shrinkWork?.cancel()
    if newHeight >= height {
      height = newHeight
      layout()
    } else {
      let work = DispatchWorkItem { [weak self] in
        self?.height = newHeight
        self?.layout()
      }
      shrinkWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }
  }

  /// Pins the panel to the bottom-right of the visible frame (clear of the Dock), at a fixed
  /// picture-in-picture width regardless of screen size.
  private func layout() {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let visible = screen.visibleFrame
    let size = CGSize(width: Self.width, height: min(height, visible.height - 2 * Self.margin))
    panel.setFrame(
      CGRect(
        x: visible.maxX - size.width - Self.margin, y: visible.minY + Self.margin, width: size.width,
        height: size.height), display: true)
  }
}
