import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@Suite("Pane selection and history", .timeLimit(.minutes(1)))
struct SelectionAndHistoryTests {
  @Test("copy preserves Unicode, skips wide continuations, and joins only soft wraps")
  func unicodeSelection() async {
    let emulator = TerminalEmulator(size: .init(width: 6, height: 4))
    _ = await emulator.feed(Array("a界e\u{301}xyZ\r\nend".utf8))
    let frame = await emulator.captureSnapshot()
    var selection = TerminalTextSelection(snapshot: frame, anchor: .zero)
    selection.extend(to: .init(x: 5, y: 2))
    #expect(selection.text == "a界e\u{301}xyZ\nend")
    let frozen = selection.text
    _ = await emulator.feed(Array("\u{1B}[2JCHANGED".utf8))
    #expect(selection.text == frozen)
    var wide = TerminalTextSelection(snapshot: frame, anchor: .init(x: 2, y: 0))
    wide.extend(to: .init(x: 2, y: 0))
    #expect(wide.text == "界")
  }

  @Test("browsing keeps an absolute anchor through output and bounded eviction")
  func historyAnchor() async {
    let first = TerminalEmulator(size: .init(width: 10, height: 3), scrollbackLimit: 8)
    let second = TerminalEmulator(size: .init(width: 10, height: 3), scrollbackLimit: 8)
    _ = await first.feed(Array((0..<7).map { "line\($0)\r\n" }.joined().utf8))
    await first.scroll(by: -3)
    let anchored = await first.captureSnapshot()
    #expect(!anchored.isFollowingOutput)
    _ = await first.feed(Array("line7\r\n".utf8))
    let more = await first.captureSnapshot()
    #expect(more.firstRow == anchored.firstRow)
    #expect(more.grid == anchored.grid)
    _ = await first.feed(Array((8..<1_000).map { "line\($0)\r\n" }.joined().utf8))
    let evicted = await first.captureSnapshot()
    #expect(evicted.retainedRows.count <= 11)
    #expect(evicted.firstRow == evicted.retainedRows.lowerBound)
    #expect(!evicted.isFollowingOutput)
    #expect(await second.captureSnapshot().isFollowingOutput)
    await first.resumeFollowingOutput()
    let live = await first.captureSnapshot()
    #expect(live.isFollowingOutput)
    #expect(live.grid.cells.map { String($0.map(\.character)) }.joined().contains("line999"))
  }

  @Test("resize, reset and alternate buffers start a new viewport epoch")
  func viewportEpoch() async {
    let emulator = TerminalEmulator(size: .init(width: 8, height: 3), scrollbackLimit: 20)
    _ = await emulator.feed(Array(String(repeating: "row\r\n", count: 10).utf8))
    await emulator.scroll(by: -4)
    let previous = await emulator.captureSnapshot()
    await emulator.resize(.init(width: 4, height: 4))
    let resized = await emulator.captureSnapshot()
    #expect(resized.epoch != previous.epoch)
    #expect(resized.isFollowingOutput)
    _ = await emulator.feed(Array("\u{1B}[?1049hALT".utf8))
    await emulator.scroll(by: -5)
    let alternate = await emulator.captureSnapshot()
    #expect(alternate.buffer == .alternate)
    #expect(alternate.isFollowingOutput)
    #expect(alternate.epoch != resized.epoch)
    _ = await emulator.feed(Array("\u{1B}c".utf8))
    #expect(await emulator.captureSnapshot().epoch != alternate.epoch)
  }
}
