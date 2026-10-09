import SwiftTUIRuntime
import SwiftTUITerminalEmulation

/// Chooses whether a focused key belongs to the embedding host or its child.
public enum TerminalViewKeyDisposition: Equatable, Sendable {
  case forwardToChild
  case handledByHost
}

public struct TerminalView<Session: TerminalSession>: View {
  private let session: Session
  private let keyRouting: @MainActor @Sendable (KeyPress) -> TerminalViewKeyDisposition
  private let onTitleChange: (@MainActor @Sendable (String) -> Void)?
  private let onExit: (@MainActor @Sendable (TerminalExitReason) -> Void)?

  public init(
    session: Session,
    onTitleChange: (@MainActor @Sendable (String) -> Void)? = nil,
    onExit: (@MainActor @Sendable (TerminalExitReason) -> Void)? = nil
  ) {
    self.init(
      session: session, keyRouting: { _ in .forwardToChild }, onTitleChange: onTitleChange,
      onExit: onExit)
  }

  /// The host interceptor runs before selection, history, or child encoding.
  public init(
    session: Session,
    keyRouting: @escaping @MainActor @Sendable (KeyPress) -> TerminalViewKeyDisposition,
    onTitleChange: (@MainActor @Sendable (String) -> Void)? = nil,
    onExit: (@MainActor @Sendable (TerminalExitReason) -> Void)? = nil
  ) {
    self.session = session
    self.keyRouting = keyRouting
    self.onTitleChange = onTitleChange
    self.onExit = onExit
  }

  public var body: some View {
    TerminalViewContent<Session, Int>(
      session: session, keyRouting: keyRouting, onTitleChange: onTitleChange, onExit: onExit,
      focusBinding: nil, focusValue: nil
    )
  }

  /// Binds the host's focus model to the same member that owns pane interaction.
  @MainActor
  public func hostFocused<Value: Hashable>(
    _ binding: FocusState<Value?>.Binding,
    equals value: Value
  ) -> some View {
    TerminalViewContent(
      session: session, keyRouting: keyRouting, onTitleChange: onTitleChange, onExit: onExit,
      focusBinding: binding, focusValue: value
    )
  }
}

private struct TerminalViewContent<Session: TerminalSession, Focus: Hashable>: View {
  @FocusState private var localFocus: Bool
  @State private var updateGeneration: UInt64 = 0
  @State private var selection: TerminalTextSelection?
  @State private var paneTitle = "Terminal"

  let session: Session
  let keyRouting: @MainActor @Sendable (KeyPress) -> TerminalViewKeyDisposition
  let onTitleChange: (@MainActor @Sendable (String) -> Void)?
  let onExit: (@MainActor @Sendable (TerminalExitReason) -> Void)?
  let focusBinding: FocusState<Focus?>.Binding?
  let focusValue: Focus?

  var body: some View {
    _ = updateGeneration
    let frame = session.cachedTerminalSnapshot
    let isFocused = focusBinding.map { $0.wrappedValue == focusValue } ?? localFocus
    return EnvironmentReader(\.terminalEventHandlers) { handlers in
      EnvironmentReader(\.clipboardWriteAction) { clipboard in
        // Wheel and drag routes have distinct members; neither replaces the other.
        VStack(spacing: 0) {
          focused(
            content(handlers: handlers, clipboard: clipboard)
              .focusable(true)
              .onKeyPress { key in
                handleKey(
                  key, frame: session.cachedTerminalSnapshot, clipboard: clipboard,
                  handlers: handlers)
              }
              .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                  let source = selection?.snapshot ?? frame
                  var next = TerminalTextSelection(
                    snapshot: source, anchor: cell(value.startLocation))
                  next.extend(to: cell(value.location))
                  selection = next
                },
                including: selection != nil || !frame.mouseTracking ? .all : .none
              )
          )
        }
        .onScrollWheel { wheel in
          guard isFocused, selection != nil || !frame.mouseTracking || !frame.isFollowingOutput
          else { return .ignored }
          selection = nil
          Task { await session.scroll(by: wheel.deltaY) }
          return .handled
        }
        .accessibilityRepresentation {
          TerminalPaneReview(
            session: session, frame: frame, title: paneTitle,
            clipboard: clipboard, handlers: handlers
          )
          .id(ObjectIdentifier(session))
        }
      }
    }
  }

  @ViewBuilder
  private func focused<Content: View>(_ view: Content) -> some View {
    if let focusBinding, let focusValue {
      view.focused(focusBinding, equals: focusValue)
    } else {
      view.focused($localFocus)
    }
  }

  private func content(handlers: TerminalEventHandlers, clipboard: ClipboardWriteAction)
    -> some View
  {
    GeometryReader { proxy in
      let frame = session.cachedTerminalSnapshot
      ForeignSurface(payload: SessionGridPayload(grid: selection?.highlightedGrid ?? frame.grid))
        .overlay(alignment: .topLeading) {
          ForEach(selection?.snapshot.graphics ?? frame.graphics) { graphic in
            Image(data: graphic.png).resizable()
              .frame(width: graphic.bounds.size.width, height: graphic.bounds.size.height)
              .offset(x: graphic.bounds.origin.x, y: graphic.bounds.origin.y)
              .allowsHitTesting(false)
          }
        }
        .clipped()
        .task(id: TerminalViewLifecycleID(session: ObjectIdentifier(session), size: proxy.size)) {
          // Task-local ownership survives view-state removal and closes
          // outstanding host requests when a pane detaches or resizes.
          var activeNotifications: Set<TerminalNotificationID> = []
          defer {
            for id in activeNotifications {
              handlers.notification?(TerminalNotification(id: id, kind: .close))
            }
          }
          let events = session.events()
          try? await session.start()
          try? await session.resize(proxy.size)
          paneTitle = await session.currentTitle() ?? "Terminal"
          for await event in events {
            updateGeneration &+= 1
            if let selection, selection.snapshot.epoch != session.cachedTerminalSnapshot.epoch {
              self.selection = nil
            }
            switch event {
            case .notification(let notification):
              if notification.kind == .show {
                activeNotifications.insert(notification.id)
              } else {
                activeNotifications.remove(notification.id)
              }
              handlers.notification?(notification)
            case .titleChanged(let title):
              paneTitle = title
              onTitleChange?(title)
              handlers.titleChanged?(title)
            case .workingDirectoryChanged(let directory):
              handlers.workingDirectoryChanged?(directory)
            case .clipboardWriteRequested(let bytes):
              _ = clipboard(String(decoding: bytes, as: UTF8.self))
            default: break
            }
          }
          if case .exited(let reason) = await session.currentLifecycle() {
            onExit?(reason)
          }
        }
    }

  }

  private func cell(_ point: Point) -> CellPoint {
    CellPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
  }

  private func handleKey(
    _ key: KeyPress, frame: TerminalSnapshot, clipboard: ClipboardWriteAction,
    handlers: TerminalEventHandlers
  ) -> KeyPressResult {
    guard keyRouting(key) == .forwardToChild else { return .handled }
    if key.modifiers.contains([.ctrl, .shift]),
      key.key == .character("s") || key.key == .character("S")
    {
      selection = TerminalTextSelection(snapshot: frame, anchor: .zero)
      return .handled
    }
    if var selected = selection {
      switch key.key {
      case .escape: selection = nil
      case .return:
        let copied = clipboard(selected.text)
        handlers.copyCompleted?(copied)
      case .character(let c) where (c == "c" || c == "C") && key.modifiers.contains(.ctrl):
        let copied = clipboard(selected.text)
        handlers.copyCompleted?(copied)
      case .arrowLeft:
        selected.extend(to: CellPoint(x: selected.focus.x - 1, y: selected.focus.y))
        selection = selected
      case .arrowRight:
        selected.extend(to: CellPoint(x: selected.focus.x + 1, y: selected.focus.y))
        selection = selected
      case .arrowUp:
        selected.extend(to: CellPoint(x: selected.focus.x, y: selected.focus.y - 1))
        selection = selected
      case .arrowDown:
        selected.extend(to: CellPoint(x: selected.focus.x, y: selected.focus.y + 1))
        selection = selected
      case .home:
        selected.extend(to: CellPoint(x: 0, y: selected.focus.y))
        selection = selected
      case .end:
        selected.extend(to: CellPoint(x: frame.grid.size.width - 1, y: selected.focus.y))
        selection = selected
      default: break
      }
      return .handled
    }
    if !frame.isFollowingOutput
      || key.modifiers.contains(.shift) && (key.key == .pageUp || key.key == .pageDown)
    {
      switch key.key {
      case .escape, .end:
        Task { await session.resumeFollowingOutput() }
      case .pageUp:
        Task { await session.scroll(by: -max(1, frame.grid.size.height - 1)) }
      case .pageDown:
        Task { await session.scroll(by: max(1, frame.grid.size.height - 1)) }
      case .arrowUp: Task { await session.scroll(by: -1) }
      case .arrowDown: Task { await session.scroll(by: 1) }
      case .home: Task { await session.scroll(by: -100_000) }
      default: break
      }
      return .handled
    }
    guard let key = TerminalEmulatorKey(keyPress: key) else { return .ignored }
    Task { await session.send(key: key) }
    return .handled
  }
}

private struct TerminalViewLifecycleID: Equatable {
  var session: ObjectIdentifier
  var size: CellSize
}

// Draw trees retain the frame they rendered, so previous frames cannot read newer session state.
struct SessionGridPayload: ForeignSurfacePayload {
  let grid: ForeignGrid
}
