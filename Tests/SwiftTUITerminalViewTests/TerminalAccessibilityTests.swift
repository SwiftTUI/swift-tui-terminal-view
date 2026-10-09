import SwiftTUIRuntime
import SwiftTUITerminalEmulation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUITerminalView

@Suite("Terminal pane accessibility", .timeLimit(.minutes(1)))
struct TerminalAccessibilityTests {
  @Test("logical caret remains attached to live input while earlier output is reviewed")
  func caretAndHistory() async {
    let emulator = TerminalEmulator(size: .init(width: 12, height: 3), scrollbackLimit: 20)
    _ = await emulator.feed(Array("first\r\nsecond\r\nthird\r\nfourth".utf8))
    let live = await emulator.captureSnapshot()
    #expect(live.caret == CellPoint(x: 6, y: 3))
    await emulator.scroll(by: -1)
    let review = await emulator.captureSnapshot()
    #expect(review.firstRow == 0)
    #expect(review.caret == live.caret)
    #expect(!review.isFollowingOutput)
    _ = await emulator.feed(Array("!".utf8))
    #expect(await emulator.captureSnapshot().caret == CellPoint(x: 7, y: 3))
    #expect(TerminalReviewText.output(review).contains("first"))
  }

  @Test("review preserves Unicode and soft wraps, excludes controls, and bounds output")
  func safeText() async {
    let emulator = TerminalEmulator(size: .init(width: 6, height: 4))
    _ = await emulator.feed(Array("a界e\u{301}xyZ\r\nend".utf8))
    let frame = await emulator.captureSnapshot()
    #expect(TerminalReviewText.output(frame).hasPrefix("a界e\u{301}xyZ\nend"))
    #expect(
      TerminalReviewText.sanitized("hi\u{1B}\u{7}\u{9B}\u{202E}界\nend", limit: 100) == "hi界\nend")
    #expect(
      TerminalReviewText.sanitized(String(repeating: "x", count: 100_000), limit: 32) == String(
        repeating: "x", count: 32) + "\nReview truncated")
  }

  @MainActor
  @Test("default pane exposes bounded review without changing its native focus membership")
  func paneSemantics() throws {
    let artifacts = DefaultRenderer().render(
      TerminalView(session: AccessibilitySession()),
      context: ResolveContext(identity: Identity(components: [.named("TerminalPane")])),
      proposal: .init(width: 20, height: 4))
    let nodes = artifacts.semanticSnapshot.accessibilityNodes
    for name in [
      "Terminal pane", "Terminal", "Copy reviewed output", "Freeze output review",
      "Earlier output", "Later output", "Follow latest output", "Enter child line input",
    ] {
      #expect(nodes.contains { $0.label == name })
    }
    #expect(
      nodes.contains { $0.label?.contains("hello 界") == true }, "\(nodes.map { $0.label ?? "nil" })"
    )
    #expect(
      nodes.contains { $0.label == "Child caret: row 1, column 8" },
      "\(nodes.map { $0.label ?? "nil" })")
    #expect(nodes.count < 30)
    #expect(artifacts.semanticSnapshot.focusRegions.count == 1)
  }
}

private final class AccessibilitySession: TerminalSession {
  var cachedSnapshot: ForeignGrid {
    ForeignGrid(
      size: .init(width: 8, height: 1), cells: [Array("hello 界 ").map { RasterCell(character: $0) }]
    )
  }
  var cachedTerminalSnapshot: TerminalSnapshot {
    TerminalSnapshot(generation: 1, grid: cachedSnapshot, caret: .init(x: 7, y: 0))
  }
  func start() async throws {}
  func snapshot() async -> ForeignGrid { cachedSnapshot }
  func currentTitle() async -> String? { nil }
  func currentWorkingDirectory() async -> String? { nil }
  func currentLifecycle() async -> TerminalLifecycle { .running }
  func send(key: TerminalEmulatorKey) async {}
  func send(paste: String) async {}
  func send(mouse: TerminalEmulatorMouse) async {}
  func resize(_ size: CellSize) async throws {}
  func events() -> AsyncStream<TerminalEmulatorEvent> { AsyncStream { $0.finish() } }
}
