import SwiftTUIRuntime
public import SwiftTUITerminalEmulation

struct TerminalEventHandlers: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  var notification: (@MainActor @Sendable (TerminalNotification) -> Void)?
  var copyCompleted: (@MainActor @Sendable (Bool) -> Void)?
  var titleChanged: (@MainActor @Sendable (String) -> Void)?
  var workingDirectoryChanged: (@MainActor @Sendable (String) -> Void)?

  var description: String {
    "TerminalEventHandlers(copyCompleted:\(copyCompleted != nil),notification:\(notification != nil),titleChanged:\(titleChanged != nil),workingDirectoryChanged:\(workingDirectoryChanged != nil))"
  }

  var debugDescription: String {
    description
  }
}

private enum TerminalEventHandlersKey: EnvironmentKey {
  static let defaultValue = TerminalEventHandlers()
}

extension EnvironmentValues {
  var terminalEventHandlers: TerminalEventHandlers {
    get { self[TerminalEventHandlersKey.self] }
    set { self[TerminalEventHandlersKey.self] = newValue }
  }
}

extension View {
  @MainActor
  public func terminalTitleChanged(
    _ handler: @escaping @MainActor @Sendable (String) -> Void
  ) -> some View {
    transformEnvironment(\.terminalEventHandlers) { handlers in
      handlers.titleChanged = handler
    }
  }

  @MainActor
  public func terminalWorkingDirectoryChanged(
    _ handler: @escaping @MainActor @Sendable (String) -> Void
  ) -> some View {
    transformEnvironment(\.terminalEventHandlers) { handlers in
      handlers.workingDirectoryChanged = handler
    }
  }
}

extension View {
  /// Reports whether an explicit pane selection copy was accepted by the host clipboard.
  @MainActor
  public func terminalCopyCompleted(_ handler: @escaping @MainActor @Sendable (Bool) -> Void)
    -> some View
  {
    transformEnvironment(\.terminalEventHandlers) { $0.copyCompleted = handler }
  }
}

extension View {
  /// Handles pane-owned OSC 99 requests. The host decides presentation and foreground policy.
  /// Close requests are also delivered when the pane disappears or its session exits.
  @MainActor
  public func terminalNotification(
    _ handler: @escaping @MainActor @Sendable (TerminalNotification) -> Void
  ) -> some View {
    transformEnvironment(\.terminalEventHandlers) { $0.notification = handler }
  }
}
