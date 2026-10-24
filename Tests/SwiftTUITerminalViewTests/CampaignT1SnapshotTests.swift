import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@Suite("Campaign T1 selection, history and snapshots", .serialized, .timeLimit(.minutes(1)))
struct CampaignT1SnapshotTests {
  @Test(arguments: Array(1...10))
  func selection(id: Int) async {
    let emulator = TerminalEmulator(size: .init(width: 6, height: 4))
    let input: String
    switch id {
    case 2, 3: input = "a界b"
    case 4: input = "ae\u{301}z"
    case 5: input = "ab  \r\ncd"
    case 6: input = "abcd  Z"
    case 7, 10: input = "abc\r\ndef"
    default: input = "abcdef"
    }
    _ = await emulator.feed(Array(input.utf8))
    let frame = await emulator.captureSnapshot()
    var selection: TerminalTextSelection
    switch id {
    case 1:
      selection = .init(snapshot: frame, anchor: .init(x: 3, y: 0))
      selection.extend(to: .init(x: 1, y: 0))
      #expect(selection.text == "bcd")
    case 2, 3:
      selection = .init(snapshot: frame, anchor: .init(x: id == 2 ? 1 : 2, y: 0))
      #expect(selection.text == "界")
      #expect(selection.highlightedGrid.cells[0][1].style?.backgroundColor == .blue)
      #expect(selection.highlightedGrid.cells[0][2].style?.backgroundColor == .blue)
    case 4:
      selection = .init(snapshot: frame, anchor: .init(x: 1, y: 0))
      #expect(selection.text == "e\u{301}")
      #expect(selection.text.count == 1)
    case 5, 6:
      selection = .init(snapshot: frame, anchor: .zero)
      selection.extend(to: .init(x: 5, y: 1))
      #expect(selection.text == (id == 5 ? "ab\ncd" : "abcd  Z"))
    case 7:
      selection = .init(snapshot: frame, anchor: .init(x: 1, y: 1))
      selection.extend(to: .init(x: 1, y: 0))
      var forward = TerminalTextSelection(snapshot: frame, anchor: .init(x: 1, y: 0))
      forward.extend(to: .init(x: 1, y: 1))
      #expect(selection.text == "bc\nde")
      #expect(
        selection.text == forward.text && selection.highlightedGrid == forward.highlightedGrid)
    case 8:
      selection = .init(snapshot: frame, anchor: .zero)
      selection.extend(to: .init(x: 3, y: 0))
      _ = await emulator.feed(Array("\u{1B}[H\u{1B}[2JOTHER".utf8))
      #expect(selection.text == "abcd")
      #expect(selection.snapshot == frame)
      #expect(await emulator.snapshot() != frame.grid)
    case 9:
      selection = .init(snapshot: frame, anchor: .init(x: 1, y: 0))
      selection.extend(to: .init(x: 3, y: 0))
      #expect(
        selection.highlightedGrid.cells[0].map(\.character) == frame.grid.cells[0].map(\.character))
      #expect(selection.highlightedGrid.cells[0][2].style?.backgroundColor == .blue)
      #expect(selection.highlightedGrid.cells[0][0] == frame.grid.cells[0][0])
      #expect(selection.snapshot.grid == frame.grid)
    default:
      selection = .init(snapshot: frame, anchor: .init(x: -8, y: -4))
      selection.extend(to: .init(x: 40, y: 1))
      #expect(selection.anchor == .zero && selection.focus == .init(x: 5, y: 1))
      #expect(selection.text == "abc\ndef")
    }
  }

  @Test(arguments: Array(11...20))
  func history(id: Int) async {
    let emulator = TerminalEmulator(
      size: .init(width: 10, height: 3), scrollbackLimit: id == 11 ? 0 : 4)
    _ = await emulator.feed(Array((0..<8).map { "row\($0)\r\n" }.joined().utf8))
    let initial = await emulator.captureSnapshot()
    if id == 11 {
      #expect(initial.retainedRows.count <= 3)
      await emulator.scroll(by: -20)
      #expect(await emulator.captureSnapshot().firstRow == initial.firstRow)
      return
    }
    if id == 12 {
      _ = await emulator.feed(Array((8..<16).map { "row\($0)\r\n" }.joined().utf8))
      #expect(await emulator.captureSnapshot().retainedRows.count <= 7)
      return
    }
    await emulator.scroll(by: -2)
    let browsing = await emulator.captureSnapshot()
    #expect(!browsing.isFollowingOutput)
    switch id {
    case 13:
      _ = await emulator.feed(Array("row8\r\n".utf8))
      let more = await emulator.captureSnapshot()
      #expect(more.firstRow == browsing.firstRow && more.grid == browsing.grid)
    case 14:
      _ = await emulator.feed(Array((8..<28).map { "row\($0)\r\n" }.joined().utf8))
      let evicted = await emulator.captureSnapshot()
      #expect(evicted.firstRow == evicted.retainedRows.lowerBound)
      #expect(!evicted.isFollowingOutput)
    case 15:
      _ = await emulator.feed(Array("latest\r\n".utf8))
      await emulator.resumeFollowingOutput()
      let live = await emulator.captureSnapshot()
      #expect(live.isFollowingOutput)
      #expect(live.grid.cells.map { String($0.map(\.character)) }.joined().contains("latest"))
    case 16:
      await emulator.scroll(by: 100)
      let edge = await emulator.captureSnapshot()
      #expect(edge.firstRow == initial.firstRow && !edge.isFollowingOutput)
      await emulator.resumeFollowingOutput()
      #expect(await emulator.captureSnapshot().isFollowingOutput)
    case 17:
      _ = await emulator.feed(Array("\u{1B}[?1049hALT".utf8))
      let alternate = await emulator.captureSnapshot()
      await emulator.scroll(by: -20)
      let scrolled = await emulator.captureSnapshot()
      #expect(scrolled.buffer == .alternate && scrolled.isFollowingOutput)
      #expect(scrolled.grid == alternate.grid && scrolled.firstRow == alternate.firstRow)
    case 18:
      await emulator.resize(.init(width: 8, height: 4))
      let resized = await emulator.captureSnapshot()
      #expect(resized.epoch != browsing.epoch && resized.isFollowingOutput)
      #expect(resized.grid.size == .init(width: 8, height: 4))
    case 19:
      _ = await emulator.feed([27, 99])
      let reset = await emulator.captureSnapshot()
      #expect(reset.epoch != browsing.epoch && reset.isFollowingOutput)
      #expect(reset.grid.cells.allSatisfy { $0.allSatisfy { $0.character == " " } })
    default:
      _ = await emulator.feed(Array("\u{1B}[?1049hALT\u{1B}[?1049l".utf8))
      let normal = await emulator.captureSnapshot()
      #expect(normal.buffer == .normal && normal.isFollowingOutput)
      #expect(normal.grid == initial.grid && normal.epoch != browsing.epoch)
    }
  }

  @Test(arguments: Array(21...30))
  func snapshots(id: Int) async {
    let emulator = TerminalEmulator(size: .init(width: 12, height: 4), scrollbackLimit: 8)
    if (26...29).contains(id) {
      let input: String
      switch id {
      case 26: input = "a界e\u{301}🙂Z"
      case 27: input = "\u{1B}[1;31mRED\u{1B}[0mplain"
      case 28: input = "abcdef\u{1B}[1;3H\u{1B}[KXY"
      default: input = "NORMAL\u{1B}[?1049hALT\u{1B}[?1049l!"
      }
      let bytes = Array(input.utf8)
      _ = await emulator.feed(bytes)
      let expected = await emulator.captureSnapshot()
      for split in 1..<bytes.count {
        let splitEmulator = TerminalEmulator(size: .init(width: 12, height: 4), scrollbackLimit: 8)
        _ = await splitEmulator.feed(Array(bytes[..<split]))
        _ = await splitEmulator.feed(Array(bytes[split...]))
        let actual = await splitEmulator.captureSnapshot()
        #expect(actual.grid == expected.grid && actual.caret == expected.caret)
        #expect(actual.buffer == expected.buffer && actual.epoch == expected.epoch)
      }
      return
    }
    _ = await emulator.feed(Array("first\r\nsecond".utf8))
    let frame = await emulator.captureSnapshot()
    switch id {
    case 21:
      _ = await emulator.feed(Array("!".utf8))
      let fed = await emulator.captureSnapshot()
      await emulator.scroll(by: -1)
      let scrolled = await emulator.captureSnapshot()
      await emulator.resize(.init(width: 10, height: 3))
      let resized = await emulator.captureSnapshot()
      #expect(
        frame.generation < fed.generation && fed.generation < scrolled.generation
          && scrolled.generation < resized.generation)
    case 22: #expect(await emulator.captureSnapshot() == frame)
    case 23:
      _ = await emulator.feed(Array("\u{1B}[?25l".utf8))
      #expect(await emulator.captureSnapshot().caret == frame.caret)
    case 24:
      _ = await emulator.feed(Array((0..<8).map { "row\($0)\r\n" }.joined().utf8))
      let live = await emulator.captureSnapshot()
      await emulator.scroll(by: -3)
      let old = await emulator.captureSnapshot()
      #expect(old.firstRow < live.firstRow && old.caret == live.caret)
    case 25:
      let text = frame.grid.cells.map { String($0.map(\.character)) }
      _ = await emulator.feed(Array("\u{1B}[H\u{1B}[2Jchanged".utf8))
      #expect(frame.grid.cells.map { String($0.map(\.character)) } == text)
      let current = await emulator.snapshot()
      #expect(frame.grid != current)
    default:
      let operations = ["!", "\u{1B}[2;1Hreplace", "\u{1B}[1;4H\u{1B}[K", "\r\nend"]
      var complete = Array("first\r\nsecond".utf8)
      for operation in operations {
        _ = await emulator.feed(Array(operation.utf8))
        _ = await emulator.captureSnapshot()
        complete += Array(operation.utf8)
      }
      let replay = TerminalEmulator(size: .init(width: 12, height: 4), scrollbackLimit: 8)
      _ = await replay.feed(complete)
      #expect(await emulator.snapshot() == replay.snapshot())
    }
  }
}
