import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@MainActor
@Suite("Campaign T1 review contracts", .serialized)
struct CampaignT1ReviewTests {
  @Test(arguments: Array(91...100))
  func review(id: Int) {
    switch id {
    case 91:
      #expect(
        TerminalReviewText.sanitized("a\u{1B}\u{7}\u{202E}界\u{2066}\ne\u{301}", limit: 40)
          == "a界\ne\u{301}")
    case 92:
      #expect(TerminalReviewText.sanitized("界éABC", limit: 3) == "界éA\nReview truncated")
    case 93:
      #expect(TerminalReviewText.sanitized("界éA", limit: 3) == "界éA")
    case 94:
      #expect(TerminalReviewText.sanitized("A", limit: 0) == "\nReview truncated")
    case 95:
      #expect(TerminalReviewText.output(.init(generation: 1, grid: .empty)).isEmpty)
    case 96...98:
      let frame = TerminalSnapshot(
        generation: 1, grid: Self.grid("hello"),
        firstRow: id == 98 ? 10 : 0, retainedRows: 0...13,
        buffer: id == 97 ? .alternate : .normal,
        caret: id == 98 ? .init(x: 3, y: 12) : nil)
      let snapshot = DefaultRenderer().render(
        TerminalView(session: T1FrameSession(frame: frame)),
        proposal: .init(width: 12, height: 4))
      let nodes = snapshot.semanticSnapshot.accessibilityNodes
      if id == 96 {
        #expect(nodes.contains { $0.label == "Child caret unavailable" })
      } else if id == 97 {
        #expect(nodes.contains { $0.label == "Earlier output" && !$0.isEnabled })
        #expect(nodes.contains { $0.label == "Later output" && !$0.isEnabled })
      } else {
        #expect(nodes.contains { $0.label == "Rows 11 through 11; normal screen" })
        #expect(nodes.contains { $0.label == "Child caret: row 13, column 4" })
      }
    case 99:
      let first = T1FrameSession(frame: .init(generation: 1, grid: Self.grid("FIRST")))
      let second = T1FrameSession(frame: .init(generation: 1, grid: Self.grid("SECOND")))
      let snapshot = DefaultRenderer().render(
        HStack {
          TerminalView(session: first).frame(width: 12, height: 2)
          TerminalView(session: second).frame(width: 12, height: 2)
        }, proposal: .init(width: 25, height: 2))
      let nodes = snapshot.semanticSnapshot.accessibilityNodes
      #expect(nodes.contains { $0.label == "FIRST" })
      #expect(nodes.contains { $0.label == "SECOND" })
      #expect(snapshot.semanticSnapshot.focusRegions.count == 2)
    default:
      let session = T1LegacySession(grid: Self.grid("legacy"))
      #expect(session.cachedTerminalSnapshot.grid == session.cachedSnapshot)
      #expect(
        session.cachedTerminalSnapshot.isFollowingOutput
          && session.cachedTerminalSnapshot.caret == nil)
    }
  }

  private static func grid(_ text: String) -> ForeignGrid {
    .init(
      size: .init(width: 12, height: 1),
      cells: [
        Array((text + String(repeating: " ", count: 12)).prefix(12)).map {
          RasterCell(character: $0)
        }
      ])
  }
}

private final class T1FrameSession: TerminalSession {
  let frame: TerminalSnapshot
  init(frame: TerminalSnapshot) { self.frame = frame }
  var cachedSnapshot: ForeignGrid { frame.grid }
  var cachedTerminalSnapshot: TerminalSnapshot { frame }
  func start() async throws {}
  func snapshot() async -> ForeignGrid { frame.grid }
  func currentTitle() async -> String? { nil }
  func currentWorkingDirectory() async -> String? { nil }
  func currentLifecycle() async -> TerminalLifecycle { .running }
  func send(key: TerminalEmulatorKey) async {}
  func send(paste: String) async {}
  func send(mouse: TerminalEmulatorMouse) async {}
  func resize(_ size: CellSize) async throws {}
  func events() -> AsyncStream<TerminalEmulatorEvent> { AsyncStream { $0.finish() } }
}

private final class T1LegacySession: TerminalSession {
  let cachedSnapshot: ForeignGrid
  init(grid: ForeignGrid) { self.cachedSnapshot = grid }
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
