public import SwiftTUIRuntime
public import SwiftTUITerminalEmulation

public protocol TerminalSession: AnyObject, Sendable {
  var cachedSnapshot: ForeignGrid { get }
  var cachedTerminalSnapshot: TerminalSnapshot { get }
  func scroll(by lines: Int) async
  func resumeFollowingOutput() async

  func start() async throws
  func snapshot() async -> ForeignGrid
  func currentTitle() async -> String?
  func currentWorkingDirectory() async -> String?
  func currentLifecycle() async -> TerminalLifecycle
  func send(key: TerminalEmulatorKey) async
  func send(paste: String) async
  func send(mouse: TerminalEmulatorMouse) async
  func resize(_ size: CellSize) async throws
  func events() -> AsyncStream<TerminalEmulatorEvent>
}

public enum TerminalLifecycle: Sendable, Equatable {
  case notStarted
  case running
  case exited(reason: TerminalExitReason)
}

public enum TerminalExitReason: Sendable, Equatable {
  case normal(code: Int32)
  case signal(Int32)
  case sessionClosed
}

extension TerminalSession {
  /// Compatibility defaults for custom sessions that expose only a live grid.
  public var cachedTerminalSnapshot: TerminalSnapshot {
    TerminalSnapshot(generation: 0, grid: cachedSnapshot)
  }
  public func scroll(by lines: Int) async {}
  public func resumeFollowingOutput() async {}
}
