// A neutral gradient behind the bottom-right corner so README screenshots show the glass over a
// controlled background instead of whatever is on screen. Floats below Tot's status-bar panel.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let visible = NSScreen.main!.visibleFrame
let frame = CGRect(x: visible.maxX - 560, y: visible.minY, width: 560, height: 820)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.level = .floating
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
let gradient = CAGradientLayer()
gradient.colors = [
  NSColor(srgbRed: 0.36, green: 0.42, blue: 0.62, alpha: 1).cgColor,
  NSColor(srgbRed: 0.78, green: 0.56, blue: 0.50, alpha: 1).cgColor,
]
gradient.startPoint = CGPoint(x: 0, y: 1)
gradient.endPoint = CGPoint(x: 1, y: 0)
let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
view.wantsLayer = true
view.layer = gradient
window.contentView = view
window.orderFrontRegardless()
app.run()
