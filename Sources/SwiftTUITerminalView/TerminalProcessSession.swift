import SwiftTUIPTYPrimitives
public import SwiftTUIRuntime
public import SwiftTUITerminalEmulation
import Synchronization

public final class TerminalProcessSession: TerminalSession {
  private let pty: ChildProcessPty
  private let emulator: TerminalEmulator
  private let state: TerminalProcessSessionStateStore
  private let eventBroadcaster = TerminalEventBroadcaster()

  public init(
    command: String,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    workingDirectory: String? = nil,
    initialSize: CellSize,
    scrollbackLimit: Int = 2_000
  ) {
    self.pty = ChildProcessPty(
      executable: command,
      arguments: arguments,
      environment: environment,
      workingDirectory: workingDirectory,
      initialSize: initialSize
    )
    self.emulator = TerminalEmulator(size: initialSize, scrollbackLimit: scrollbackLimit)
    self.state = TerminalProcessSessionStateStore(
      cachedSnapshot: Self.emptyGrid(size: initialSize)
    )
  }

  public var cachedSnapshot: ForeignGrid {
    state.cachedSnapshot
  }

  public var cachedTerminalSnapshot: TerminalSnapshot { state.cachedTerminalSnapshot }

  public func scroll(by lines: Int) async {
    await emulator.scroll(by: lines)
    _ = await snapshot()
  }

  public func resumeFollowingOutput() async {
    await emulator.resumeFollowingOutput()
    _ = await snapshot()
  }

  public func start() async throws {
    let shouldStart = state.markStarting()
    guard shouldStart else {
      return
    }

    do {
      try await pty.start()
    } catch {
      state.markExited(reason: .sessionClosed)
      eventBroadcaster.finish()
      throw error
    }

    guard let pair = await pty.pair else {
      state.markExited(reason: .sessionClosed)
      eventBroadcaster.finish()
      return
    }

    let task = Task { [pty, emulator, state, eventBroadcaster] in
      // The PTY consumer never waits for frame cadence. A single pending signal
      // coalesces snapshots, while every byte and ordered metadata event is kept.
      let (updates, updateContinuation) = AsyncStream<Void>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      let publication = Task {
        for await _ in updates {
          let frame = await emulator.captureSnapshot()
          if state.setCachedSnapshot(frame) {
            eventBroadcaster.publish(.contentChanged)
          }
          try? await Task.sleep(for: .milliseconds(16))
        }
      }
      let stream = await pair.read()
      for await chunk in stream {
        let events = await emulator.feed(chunk)
        state.apply(events: events)
        updateContinuation.yield(())
        for event in events {
          eventBroadcaster.publish(event)
          if case .clientReply(let replyBytes) = event {
            try? await pair.write(replyBytes)
          }
        }
      }

      updateContinuation.finish()
      await publication.value
      let exitStatus = await pty.waitForExit()
      state.markExited(reason: Self.reason(from: exitStatus))
      eventBroadcaster.finish()
    }

    state.setPumpTask(task)
  }

  public func snapshot() async -> ForeignGrid {
    let snapshot = await emulator.captureSnapshot()
    if state.setCachedSnapshot(snapshot) {
      eventBroadcaster.publish(.contentChanged)
    }
    return snapshot.grid
  }

  public func currentTitle() async -> String? {
    state.title
  }

  public func currentWorkingDirectory() async -> String? {
    state.workingDirectory
  }

  public func currentLifecycle() async -> TerminalLifecycle {
    state.lifecycle
  }

  /// Requests termination of the child process group backing this session.
  ///
  /// Calling this before ``start()`` closes the session without launching a
  /// child. Subsequent calls to ``start()`` are no-ops. If startup has begun
  /// but has not installed its process identifier yet, the signal is retained
  /// and delivered as soon as the child is available.
  public func terminate(signal: Int32 = 15) async {
    switch state.requestTermination() {
    case .closeBeforeStart:
      eventBroadcaster.finish()
    case .signalRunningProcess:
      await pty.requestSignal(signal)
    case .alreadyExited:
      break
    }
  }

  public func send(key: TerminalEmulatorKey) async {
    let bytes = await emulator.encode(key: key)
    guard !bytes.isEmpty, let pair = await pty.pair else {
      return
    }
    try? await pair.write(bytes)
  }

  public func send(paste: String) async {
    let bytes = await emulator.encode(paste: paste)
    guard !bytes.isEmpty, let pair = await pty.pair else {
      return
    }
    try? await pair.write(bytes)
  }

  public func send(mouse: TerminalEmulatorMouse) async {
    let bytes = await emulator.send(mouse: mouse)
    guard !bytes.isEmpty, let pair = await pty.pair else {
      return
    }
    try? await pair.write(bytes)
  }

  public func resize(_ size: CellSize) async throws {
    guard let pair = await pty.pair else {
      return
    }

    try await pair.resize(size)
    await emulator.resize(size)
    _ = await snapshot()
    eventBroadcaster.publish(.sizeReported(size))
  }

  public func events() -> AsyncStream<TerminalEmulatorEvent> {
    eventBroadcaster.stream()
  }

  private static func reason(from exitStatus: ChildProcessPty.ExitStatus) -> TerminalExitReason {
    switch exitStatus {
    case .exited(let code):
      return .normal(code: code)
    case .signalled(let signal):
      return .signal(signal)
    case .unknown:
      return .sessionClosed
    }
  }

  private static func emptyGrid(size: CellSize) -> ForeignGrid {
    let row = Array(repeating: RasterCell.empty, count: max(0, size.width))
    return ForeignGrid(
      size: size,
      cells: Array(repeating: row, count: max(0, size.height))
    )
  }
}

private final class TerminalProcessSessionStateStore: Sendable {
  private let storage: Mutex<TerminalProcessSessionState>

  init(cachedSnapshot: ForeignGrid) {
    storage = Mutex(TerminalProcessSessionState(cachedSnapshot: cachedSnapshot))
  }

  var cachedSnapshot: ForeignGrid {
    storage.withLock { $0.cachedSnapshot }
  }

  var cachedTerminalSnapshot: TerminalSnapshot {
    storage.withLock {
      $0.terminalSnapshot ?? TerminalSnapshot(generation: 0, grid: $0.cachedSnapshot)
    }
  }

  var title: String? {
    storage.withLock { $0.title }
  }

  var workingDirectory: String? {
    storage.withLock { $0.workingDirectory }
  }

  var lifecycle: TerminalLifecycle {
    storage.withLock { $0.lifecycle }
  }

  func markStarting() -> Bool {
    storage.withLock { state in
      switch state.lifecycle {
      case .notStarted:
        state.lifecycle = .running
        return state.pumpTask == nil
      case .running, .exited:
        return false
      }
    }
  }

  func requestTermination() -> TerminalProcessTerminationDisposition {
    storage.withLock { state in
      switch state.lifecycle {
      case .notStarted:
        state.lifecycle = .exited(reason: .sessionClosed)
        return .closeBeforeStart
      case .running:
        return .signalRunningProcess
      case .exited:
        return .alreadyExited
      }
    }
  }

  func markExited(reason: TerminalExitReason) {
    storage.withLock { state in
      state.lifecycle = .exited(reason: reason)
      state.pumpTask = nil
    }
  }

  func setPumpTask(_ task: Task<Void, Never>) {
    storage.withLock { $0.pumpTask = task }
  }

  @discardableResult
  func setCachedSnapshot(_ snapshot: TerminalSnapshot) -> Bool {
    storage.withLock { state in
      guard snapshot.generation >= state.snapshotGeneration else { return false }
      state.snapshotGeneration = snapshot.generation
      let previous = state.terminalSnapshot
      state.terminalSnapshot = snapshot
      let changed =
        state.cachedSnapshot != snapshot.grid
        || previous?.firstRow != snapshot.firstRow || previous?.epoch != snapshot.epoch
        || previous?.isFollowingOutput != snapshot.isFollowingOutput
        || previous?.mouseTracking != snapshot.mouseTracking
        || previous?.graphics != snapshot.graphics
      state.cachedSnapshot = snapshot.grid
      guard changed else { return false }
      return true
    }
  }

  func apply(events: [TerminalEmulatorEvent]) {
    storage.withLock { $0.apply(events: events) }
  }
}

private enum TerminalProcessTerminationDisposition {
  case closeBeforeStart
  case signalRunningProcess
  case alreadyExited
}

private struct TerminalProcessSessionState: Sendable {
  var lifecycle: TerminalLifecycle = .notStarted
  var title: String?
  var workingDirectory: String?
  var cachedSnapshot: ForeignGrid
  var snapshotGeneration: UInt64 = 0
  var terminalSnapshot: TerminalSnapshot?
  var pumpTask: Task<Void, Never>?

  mutating func apply(events: [TerminalEmulatorEvent]) {
    for event in events {
      switch event {
      case .titleChanged(let newTitle):
        title = newTitle
      case .workingDirectoryChanged(let directory):
        workingDirectory = directory
      default:
        break
      }
    }
  }
}

private final class TerminalEventBroadcaster: Sendable {
  private let state = Mutex(TerminalEventBroadcasterState())

  func stream() -> AsyncStream<TerminalEmulatorEvent> {
    AsyncStream { continuation in
      let id = state.withLock { state -> Int? in
        guard !state.isFinished else {
          return nil
        }
        let id = state.nextID
        state.nextID += 1
        state.continuations[id] = continuation
        return id
      }

      guard let id else {
        // Subscriptions after `finish()` end immediately: a consumer that
        // arrives after the session exited (a pane revisited on a hidden
        // tab) must observe the exit instead of awaiting a stream nobody
        // will ever finish.
        continuation.finish()
        return
      }

      continuation.onTermination = { @Sendable [weak self] _ in
        self?.removeContinuation(id: id)
      }
    }
  }

  func publish(_ event: TerminalEmulatorEvent) {
    let continuations = state.withLock { Array($0.continuations.values) }
    for continuation in continuations {
      continuation.yield(event)
    }
  }

  func finish() {
    let continuations = state.withLock { state in
      let continuations = Array(state.continuations.values)
      state.continuations.removeAll()
      state.isFinished = true
      return continuations
    }
    for continuation in continuations {
      continuation.finish()
    }
  }

  private func removeContinuation(id: Int) {
    state.withLock { $0.continuations[id] = nil }
  }
}

private struct TerminalEventBroadcasterState {
  var nextID = 0
  var isFinished = false
  var continuations: [Int: AsyncStream<TerminalEmulatorEvent>.Continuation] = [:]
}
