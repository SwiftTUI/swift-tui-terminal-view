import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUITerminalView

@MainActor
@Suite("TerminalView layout", .timeLimit(.minutes(1)))
struct TerminalViewLayoutTests {
  @Test("TerminalView accepts the parent's full proposal")
  func acceptsProposal() {
    let session = StubTerminalSession(grid: ForeignGrid.empty)
    let artifacts = DefaultRenderer().render(
      TerminalView(session: session),
      proposal: ProposedSize(width: 40, height: 12)
    )

    #expect(artifacts.rasterSurface.size == CellSize(width: 40, height: 12))
  }

  @Test("the assigned surface renders the complete child grid")
  func emitsForeignSurface() {
    let row = Array(repeating: RasterCell(character: "x"), count: 4)
    let grid = ForeignGrid(
      size: CellSize(width: 4, height: 2),
      cells: Array(repeating: row, count: 2)
    )
    let session = StubTerminalSession(grid: grid)
    let artifacts = DefaultRenderer().render(
      TerminalView(session: session),
      proposal: ProposedSize(width: 4, height: 2)
    )

    #expect(artifacts.rasterSurface.size == grid.size)
    #expect(
      artifacts.rasterSurface.cells.map { $0.map(\.character) }
        == grid.cells.map { $0.map(\.character) })
  }

  @Test("the view lifecycle starts, resizes, and subscribes to the session once")
  func registersLifecycleTask() async throws {
    let session = StubTerminalSession(grid: ForeignGrid.empty)
    let input = ClipboardTerminalInputReader()
    let identity = Identity(components: [.named("TerminalViewLifecycleRoot")])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: identity,
      presentationSurface: ClipboardTerminalHost(),
      terminalInputReader: input,
      signalReader: ClipboardSignalReader(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity]),
      proposal: ProposedSize(width: 7, height: 3),
      exitKeyBindings: .none,
      viewBuilder: { _, _ in TerminalView(session: session) }
    )
    let task = Task { try await runLoop.run() }
    defer {
      input.finish()
      task.cancel()
    }
    await session.lifecycleSignal.wait { session.lifecycleCalls.count >= 3 }
    #expect(session.lifecycleCalls == ["events", "start", "resize"])
    #expect(session.cachedSnapshot.size == CellSize(width: 7, height: 3))
    input.finish()
    #expect(try await task.value.exitReason == .inputEnded)
  }

  @Test("plain content updates repaint alongside a sibling state change")
  func contentAndSiblingUpdate() async throws {
    let session = EventingTerminalSession(
      grid: ForeignGrid(
        size: CellSize(width: 8, height: 1),
        cells: [Array(repeating: RasterCell(character: "a"), count: 8)]
      ))
    let input = ClipboardTerminalInputReader()
    let host = ClipboardTerminalHost()
    let identity = Identity(components: [.named("TerminalContentRoot")])
    let state = StateContainer(initialState: 0, invalidationIdentities: [identity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: identity, presentationSurface: host, terminalInputReader: input,
      signalReader: ClipboardSignalReader(), stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [identity]),
      proposal: ProposedSize(width: 8, height: 2), exitKeyBindings: .none,
      viewBuilder: { value, _ in
        VStack(spacing: 0) {
          Text("state \(value)").frame(height: 1)
          TerminalView(session: session).frame(height: 1)
        }
      }
    )
    let task = Task { try await runLoop.run() }
    defer {
      input.finish()
      task.cancel()
    }
    await session.startedSignal.wait { session.isStarted }
    await host.frameSignal.wait { host.text.contains("aaaaaaaa") }
    session.setGrid(
      ForeignGrid(
        size: CellSize(width: 8, height: 1),
        cells: [Array(repeating: RasterCell(character: "b"), count: 8)]
      ))
    state.mutate { $0 = 1 }
    session.publish(.contentChanged)
    await host.frameSignal.wait { host.text.contains("bbbbbbbb") && host.text.contains("state 1") }
    #expect(!host.text.contains("aaaaaaaa"))
    input.finish()
    _ = try await task.value
  }

  @Test("notification policy can suppress one pane and receives closure on removal")
  func notificationTeardown() async throws {
    let first = EventingTerminalSession(grid: .empty)
    let second = EventingTerminalSession(grid: .empty)
    let input = ClipboardTerminalInputReader()
    let host = ClipboardTerminalHost()
    let identity = Identity(components: [.named("NotificationRoot")])
    let state = StateContainer(initialState: 0, invalidationIdentities: [identity])
    let received = Mutex<[TerminalNotification]>([])
    let signal = ConditionSignal()
    let loop = SwiftTUIRuntime.RunLoop(
      rootIdentity: identity, presentationSurface: host, terminalInputReader: input,
      signalReader: ClipboardSignalReader(), stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [identity]),
      proposal: .init(width: 20, height: 4), exitKeyBindings: .none,
      viewBuilder: { value, _ in
        HStack {
          if value == 0 {
            TerminalView(session: first).terminalNotification { request in
              received.withLock { $0.append(request) }
              signal.notify()
            }
          }
          TerminalView(session: second)  // No handler: host suppresses this pane.
        }
      }
    )
    let task = Task { try await loop.run() }
    defer {
      input.finish()
      task.cancel()
    }
    await first.startedSignal.wait { first.isStarted }
    await second.startedSignal.wait { second.isStarted }
    let firstID = TerminalNotificationID(session: "first", identifier: "same")
    first.publish(.notification(.init(id: firstID, kind: .show, title: "allowed")))
    second.publish(
      .notification(
        .init(id: .init(session: "second", identifier: "same"), kind: .show, title: "suppressed")))
    await signal.wait { received.withLock { $0.count == 1 } }
    state.mutate { $0 = 1 }
    await signal.wait { received.withLock { $0.count == 2 } }
    #expect(received.withLock { $0.map(\.kind) } == [.show, .close])
    #expect(received.withLock { $0.allSatisfy { $0.id == firstID } })
    input.finish()
    _ = try await task.value
  }

  @Test("TerminalView forwards child clipboard requests to the host clipboard action")
  func forwardsChildClipboardRequests() async throws {
    let session = EventingTerminalSession(grid: ForeignGrid.empty)
    let inputReader = ClipboardTerminalInputReader()
    let host = ClipboardTerminalHost()
    let rootIdentity = Identity(components: [.named("TerminalViewClipboardRoot")])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      signalReader: ClipboardSignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: ProposedSize(width: 8, height: 2),
      exitKeyBindings: .none,
      viewBuilder: { _, _ in
        TerminalView(session: session)
      }
    )

    let task = Task {
      try await runLoop.run()
    }

    await session.startedSignal.wait { session.isStarted }
    session.publish(.clipboardWriteRequested(Array("child text".utf8)))

    await host.clipboardSignal.wait { host.clipboardWrites == ["child text"] }

    inputReader.finish()
    let result = try await task.value
    #expect(result.exitReason == .inputEnded)
  }
}

private final class StubTerminalSession: TerminalSession {
  private let callStorage = Mutex<[String]>([])
  let lifecycleSignal = ConditionSignal()
  var lifecycleCalls: [String] { callStorage.withLock { $0 } }
  private func record(_ call: String) {
    callStorage.withLock { $0.append(call) }
    lifecycleSignal.notify()
  }
  private let snapshotStorage: Mutex<ForeignGrid>

  init(grid: ForeignGrid) {
    snapshotStorage = Mutex(grid)
  }

  var cachedSnapshot: ForeignGrid {
    snapshotStorage.withLock { $0 }
  }

  func start() async throws { record("start") }

  func snapshot() async -> ForeignGrid {
    cachedSnapshot
  }

  func currentTitle() async -> String? {
    nil
  }

  func currentWorkingDirectory() async -> String? {
    nil
  }

  func currentLifecycle() async -> TerminalLifecycle {
    .notStarted
  }

  func send(key _: TerminalEmulatorKey) async {}

  func send(paste _: String) async {}

  func send(mouse _: TerminalEmulatorMouse) async {}

  func resize(_ size: CellSize) async throws {
    snapshotStorage.withLock { grid in
      grid.size = size
    }
    record("resize")
  }

  func events() -> AsyncStream<TerminalEmulatorEvent> {
    record("events")
    return AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class EventingTerminalSession: TerminalSession, Sendable {
  private struct State: Sendable {
    var snapshot: ForeignGrid
    var continuation: AsyncStream<TerminalEmulatorEvent>.Continuation?
    var isStarted = false
  }

  private let state: Mutex<State>

  /// Notified when the session transitions to started, so a test can await
  /// that transition poll-free instead of polling `isStarted`.
  let startedSignal = ConditionSignal()

  init(grid: ForeignGrid) {
    state = Mutex(State(snapshot: grid))
  }

  var cachedSnapshot: ForeignGrid {
    state.withLock(\.snapshot)
  }

  var isStarted: Bool {
    state.withLock(\.isStarted)
  }

  func start() async throws {
    state.withLock { state in
      state.isStarted = true
    }
    startedSignal.notify()
  }

  func snapshot() async -> ForeignGrid {
    cachedSnapshot
  }

  func currentTitle() async -> String? {
    nil
  }

  func currentWorkingDirectory() async -> String? {
    nil
  }

  func currentLifecycle() async -> TerminalLifecycle {
    .running
  }

  func send(key _: TerminalEmulatorKey) async {}

  func send(paste _: String) async {}

  func send(mouse _: TerminalEmulatorMouse) async {}

  func resize(_ size: CellSize) async throws {
    state.withLock { state in
      state.snapshot.size = size
    }
  }

  func events() -> AsyncStream<TerminalEmulatorEvent> {
    AsyncStream { continuation in
      state.withLock { state in
        state.continuation = continuation
      }
    }
  }

  func setGrid(_ grid: ForeignGrid) {
    state.withLock { $0.snapshot = grid }
  }

  func publish(
    _ event: TerminalEmulatorEvent
  ) {
    state.withLock(\.continuation)?.yield(event)
  }
}

private final class ClipboardTerminalHost: PresentationSurface,
  ClipboardWritingPresentationSurface,
  Sendable
{
  var surfaceSize: CellSize { .init(width: 8, height: 2) }
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private let clipboardWritesStorage = Mutex<[String]>([])
  private let frameStorage = Mutex("")
  let frameSignal = ConditionSignal()
  var text: String { frameStorage.withLock { $0 } }

  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    frameStorage.withLock {
      $0 = surface.cells.map { String($0.map(\.character)) }.joined(separator: "\n")
    }
    frameSignal.notify()
    return TerminalPresentationMetrics(linesTouched: surface.size.height)
  }

  /// Notified after every clipboard write, so a test can await a clipboard
  /// condition poll-free instead of polling `clipboardWrites`.
  let clipboardSignal = ConditionSignal()

  var clipboardWrites: [String] {
    clipboardWritesStorage.withLock { $0 }
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  @MainActor
  func writeClipboard(_ text: String) throws -> Bool {
    clipboardWritesStorage.withLock { $0.append(text) }
    clipboardSignal.notify()
    return true
  }
}

private final class ClipboardTerminalInputReader: TerminalInputReading, Sendable {
  private struct State: Sendable {
    var continuation: AsyncStream<InputEvent>.Continuation?
    var finished = false
  }

  private let state = Mutex(State())

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let shouldFinish = state.withLock { state in
        if state.finished {
          return true
        }
        state.continuation = continuation
        return false
      }

      if shouldFinish {
        continuation.finish()
      }
    }
  }

  func finish() {
    let continuation = state.withLock { state in
      state.finished = true
      let continuation = state.continuation
      state.continuation = nil
      return continuation
    }
    continuation?.finish()
  }
}

private final class ClipboardSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
