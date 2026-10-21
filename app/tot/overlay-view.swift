import AppKit
import SwiftUI
import TotCore

struct OverlayView: View {
  let model: OverlayModel
  let settings: AppSettings
  let onContentSize: (CGSize) -> Void

  @Namespace private var glassNamespace
  @State private var isHovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let maxRows = 5
  static let detailHeight: CGFloat = 380

  var body: some View {
    GlassEffectContainer(spacing: 8) {
      VStack(alignment: .trailing, spacing: 8) {
        if let thread = model.selected {
          detail(thread)
        } else {
          ForEach(model.listed.prefix(Self.maxRows).reversed()) { row($0) }
          bar
        }
      }
      .padding(8)
    }
    .frame(width: OverlayPanelController.width)
    .onGeometryChange(for: CGSize.self, of: \.size) { onContentSize($0) }
    .frame(maxHeight: .infinity, alignment: .bottom)
    .onHover { hovering in withAnimation(.easeOut(duration: 0.2)) { isHovering = hovering } }
  }

  /// See-through clear glass while you watch something else; solid glass once the pointer arrives.
  /// Only the backing changes, so text and icons stay fully legible in both states.
  private var glass: Glass {
    let backing = Color(nsColor: .windowBackgroundColor)
      .opacity(OverlayGlass.backingOpacity(isHovering: isHovering, idleTint: settings.idleTint))
    return (isHovering ? Glass.regular : .clear).tint(backing)
  }

  private var motion: Animation? { reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.4) }

  private func perform(_ change: () -> Void) { withAnimation(motion, change) }

  // MARK: List

  private func row(_ thread: AgentThread) -> some View {
    Button {
      perform { model.select(thread) }
    } label: {
      HStack(alignment: .top, spacing: 10) {
        StatusIcon(thread: thread)
        VStack(alignment: .leading, spacing: 2) {
          Text(thread.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
          subtitle(thread).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .glassEffect(glass, in: .rect(cornerRadius: 16))
    .glassEffectID(thread.id, in: glassNamespace)
    .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
    .contextMenu {
      if !thread.isWorking { Button("Clear") { perform { model.clear(thread) } } }
    }
    .accessibilityIdentifier("thread-row")
    .accessibilityLabel(thread.title)
    .accessibilityValue(Self.state(thread))
    .accessibilityHint("Shows the last three turns")
  }

  private static func state(_ thread: AgentThread) -> String {
    if thread.isWaiting { return "Waiting" }
    if thread.isWorking { return "Running" }
    return thread.latestRun.phase == .failed ? "Failed" : "Done"
  }

  @ViewBuilder private func subtitle(_ thread: AgentThread) -> some View {
    if thread.isWorking {
      Text(
        [thread.projectName, thread.activity ?? Self.state(thread).lowercased()].compactMap(\.self).joined(
          separator: " · "))
    } else if let summary = model.summaries[thread.latestRun.completionKey] {
      Text(summary)
    } else {
      let project = thread.projectName.map { Text("\($0) · ") } ?? Text("")
      if let date = thread.latestRun.completedAt.flatMap(Self.parseDate) {
        Text(
          "\(project)\(thread.latestRun.phase == .failed ? "failed" : "done") \(date, format: .relative(presentation: .named))"
        )
      } else {
        project
      }
    }
  }

  private var bar: some View {
    HStack(spacing: 8) {
      IconButton(systemImage: "arrow.up.forward.app", label: "Open T3 Code") { open(nil) }
      VStack(alignment: .leading, spacing: 1) {
        Text(statusLine).font(.system(size: 12, weight: .medium))
        if let error = model.errorMessage {
          Label(error, systemImage: "exclamationmark.triangle")
            .font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1).help(error)
        }
      }
      Spacer(minLength: 0)
      doneToggle
      SettingsLink {
        Image(systemName: "gearshape").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
          .background(.fill.tertiary, in: .circle)
      }
      .buttonStyle(.plain)
      .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
      .help("Settings")
      .accessibilityLabel("Settings")
      if !model.working.isEmpty {
        ProgressView().controlSize(.small).accessibilityLabel("Agents working")
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .glassEffect(glass, in: .capsule)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("status-bar")
  }

  private var statusLine: String {
    let hidden = max(0, model.listed.count - Self.maxRows)
    var line =
      model.showsDone
      ? "\(model.done.count) finished" : model.working.isEmpty ? "Nothing working" : "\(model.working.count) working"
    if hidden > 0 { line += " (\(hidden) more in T3)" }
    return line
  }

  /// The done count; clicking it swaps the list between working and finished threads.
  private var doneToggle: some View {
    Button {
      perform { model.toggleDone() }
    } label: {
      Label("\(model.done.count) done", systemImage: model.showsDone ? "checkmark.circle.fill" : "checkmark.circle")
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(model.showsDone ? AnyShapeStyle(.green.opacity(0.3)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
        .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .disabled(model.done.isEmpty && !model.showsDone)
    .help(model.showsDone ? "Show working threads" : "Show finished threads")
    .accessibilityIdentifier("done-toggle")
    .accessibilityLabel("\(model.done.count) done")
    .accessibilityValue(model.showsDone ? "Shown" : "Hidden")
    .accessibilityHint(model.showsDone ? "Shows working threads" : "Shows finished threads")
  }

  // MARK: Detail

  private func detail(_ thread: AgentThread) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        IconButton(systemImage: "chevron.left", label: "Back to list") {
          perform { model.back() }
        }
        Text(thread.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        Spacer(minLength: 0)
        IconButton(systemImage: "arrow.up.forward.app", label: "Open in T3 Code") { open(thread) }
        if model.canClearSelected {
          IconButton(systemImage: "checkmark.circle", label: "Clear thread") {
            perform { model.clearSelected() }
          }
        }
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(model.turns) { turn in
            TurnView(turn: turn, model: model, perform: perform)
              .transition(entryTransition)
          }
        }
        .animation(motion, value: model.turns)
        .padding(.bottom, 22)
      }
      .defaultScrollAnchor(.bottom)
      .scrollIndicators(.never)
    }
    .padding(12)
    .frame(height: Self.detailHeight)
    .overlay(alignment: .bottomTrailing) {
      if model.isReceiving {
        ProgressView().controlSize(.small).padding(12).accessibilityLabel("Receiving messages")
      }
    }
    .glassEffect(glass, in: .rect(cornerRadius: 22))
    .glassEffectID(thread.id, in: glassNamespace)
    .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("thread-detail")
  }

  /// The oldest turn leaves upward while the newest arrives from below.
  private var entryTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity))
  }

  private func open(_ thread: AgentThread?) {
    let userdata = URL(fileURLWithPath: T3Database.defaultPath).deletingLastPathComponent()
    if let thread, settings.openThreadsInBrowser,
      let url = T3Locations.threadURL(userdata: userdata, threadID: thread.id)
    {
      NSWorkspace.shared.open(url)
    } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: T3Locations.desktopBundleID) {
      NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
  }

  nonisolated static func parseDate(_ text: String) -> Date? {
    try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
  }
}

private struct TurnView: View {
  let turn: Turn
  let model: OverlayModel
  let perform: (() -> Void) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(turn.entries) { entry in
        EntryView(entry: entry, isExpanded: model.expanded.contains(entry.id)) {
          perform { model.toggle(entry.id) }
        }
        .transition(
          reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("turn")
    .accessibilityLabel("Turn \(turn.ordinal)")
  }
}

private struct EntryView: View {
  let entry: TurnEntry
  let isExpanded: Bool
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      HStack(alignment: .top, spacing: 6) {
        if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)).padding(.top, 2) }
        Text(entry.text)
          .font(entry.kind == .tools ? .system(size: 11, design: .monospaced) : .system(size: 12))
          .lineLimit(isExpanded ? nil : 2)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .foregroundStyle(foreground)
      .padding(.horizontal, entry.kind == .user ? 10 : 2)
      .padding(.vertical, entry.kind == .user ? 7 : 1)
      .background {
        if entry.kind == .user { RoundedRectangle(cornerRadius: 12).fill(.tint.opacity(0.18)) }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("turn-entry")
    .accessibilityLabel("\(speaker): \(entry.text)")
    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    .accessibilityHint(isExpanded ? "Collapses the message" : "Expands the message")
  }

  private var speaker: String {
    switch entry.kind {
    case .user: "You"
    case .assistant: "Agent"
    case .tools: "Tools"
    case .error: "Error"
    }
  }

  private var icon: String? {
    switch entry.kind {
    case .user, .assistant: nil
    case .tools: "wrench.and.screwdriver"
    case .error: "exclamationmark.triangle.fill"
    }
  }

  private var foreground: AnyShapeStyle {
    switch entry.kind {
    case .user, .assistant: AnyShapeStyle(.primary)
    case .tools: AnyShapeStyle(.secondary)
    case .error: AnyShapeStyle(.red)
    }
  }
}

private struct StatusIcon: View {
  let thread: AgentThread
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if thread.isWaiting {
        Image(systemName: "hourglass").foregroundStyle(.orange)
      } else if thread.isWorking {
        Image(systemName: "circle.dotted.circle").foregroundStyle(.blue)
          .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
      } else if thread.latestRun.phase == .failed {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
      } else {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
      }
    }
    .font(.system(size: 14))
    .accessibilityHidden(true)
  }
}

struct IconButton: View {
  let systemImage: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 26, height: 26)
        .background(.fill.tertiary, in: .circle)
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
  }
}
