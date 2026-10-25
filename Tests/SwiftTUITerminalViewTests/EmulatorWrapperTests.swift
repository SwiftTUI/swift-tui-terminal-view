import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite("TerminalEmulator wrapper", .serialized)
struct EmulatorWrapperTests {
  @Test("emulator initializes at requested size")
  func initSize() async {
    let emulator = TerminalEmulator(size: CellSize(width: 80, height: 24))
    let snapshot = await emulator.snapshot()
    #expect(snapshot.size == CellSize(width: 80, height: 24))
  }

  @Test("empty terminal cells snapshot as raster empties")
  func emptyCellsSnapshotAsRasterEmpties() async {
    let emulator = TerminalEmulator(size: CellSize(width: 4, height: 2))
    let snapshot = await emulator.snapshot()

    #expect(
      snapshot.cells.allSatisfy { row in
        row.allSatisfy { $0 == .empty }
      })
  }

  @Test("OSC 133 shell integration markers are ignored quietly")
  func osc133MarkersAreIgnoredQuietly() async throws {
    let emulator = TerminalEmulator(size: CellSize(width: 4, height: 2))
    let output = try await captureStandardOutput {
      _ = await emulator.feed(Array("\u{1B}]133;A\u{07}".utf8))
    }

    #expect(output == "")
  }

  @Test("feeding plain ASCII produces visible cells")
  func feedAscii() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    _ = await emulator.feed(Array("hello".utf8))
    let snapshot = await emulator.snapshot()
    let firstRow = snapshot.cells[0].prefix(5).map { $0.character }
    #expect(firstRow == ["h", "e", "l", "l", "o"])
  }

  @Test("OSC 0 title changes are reported as events")
  func titleEvent() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    let oscTitle = Array("\u{1B}]0;hello-world\u{07}".utf8)
    let events = await emulator.feed(oscTitle)
    #expect(events.contains(.titleChanged("hello-world")))
  }

  @Test("OSC 7 working directory changes are reported as events")
  func workingDirectoryEvent() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    let oscDirectory = Array("\u{1B}]7;file:///tmp/swift-tui\u{07}".utf8)
    let events = await emulator.feed(oscDirectory)
    #expect(events.contains(.workingDirectoryChanged("file:///tmp/swift-tui")))
  }

  @Test("pointer cancellation emits no terminal action and leaves the next press usable")
  func mouseCancellation() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 4))
    _ = await emulator.feed(Array("\u{1B}[?1000h\u{1B}[?1006h".utf8))
    let down = TerminalEmulatorMouse(kind: .down(.primary), cell: CellPoint(x: 2, y: 1))
    let first = await emulator.send(mouse: down)
    #expect(!first.isEmpty)
    #expect(await emulator.send(mouse: .init(kind: .cancelled, cell: down.cell)).isEmpty)
    #expect(await emulator.send(mouse: down) == first)
  }

  @Test("SGR mouse protocol encodes terminal-coordinate button presses")
  func sgrMousePress() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    let events = await emulator.feed(Array("\u{1B}[?1006h".utf8))

    let bytes = await emulator.send(
      mouse: TerminalEmulatorMouse(
        kind: .down(.primary),
        cell: CellPoint(x: 4, y: 2)
      )
    )

    #expect(events.contains(.mouseModeChanged(.sgr)))
    #expect(bytes == Array("\u{1B}[<0;5;3M".utf8))
  }

  @Test("paste is bracketed when the child requests bracketed-paste")
  func bracketedPaste() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))

    #expect(await emulator.encode(paste: "hello") == Array("hello".utf8))

    _ = await emulator.feed(Array("\u{1B}[?2004h".utf8))

    #expect(
      await emulator.encode(paste: "hello")
        == Array("\u{1B}[200~hello\u{1B}[201~".utf8)
    )
  }

  @Test("plain ASCII has nil style")
  func plainCharStyle() async {
    let emulator = TerminalEmulator(size: CellSize(width: 5, height: 1))
    _ = await emulator.feed(Array("x".utf8))
    let cell = (await emulator.snapshot()).cells[0][0]
    #expect(cell.character == "x")
    #expect(cell.style == nil)
  }

  @Test("SGR red foreground produces a red cell")
  func sgrRedForeground() async {
    let emulator = TerminalEmulator(size: CellSize(width: 5, height: 1))
    _ = await emulator.feed(Array("\u{1B}[31mx\u{1B}[0m".utf8))
    let cell = (await emulator.snapshot()).cells[0][0]
    #expect(cell.style?.foregroundColor == .red)
  }

  @Test("SGR faint and blink survive cell conversion")
  func faintAndBlinkSurviveConversion() async {
    let cases: [(String, ResolvedTextStyle?)] = [
      ("\u{1B}[2m", ResolvedTextStyle(emphasis: .faint)),
      ("\u{1B}[5m", ResolvedTextStyle(emphasis: .blink)),
      ("\u{1B}[1;2m", ResolvedTextStyle(emphasis: [.bold, .faint])),
      ("\u{1B}[3;5m", ResolvedTextStyle(emphasis: [.italic, .blink])),
      ("\u{1B}[2;5m\u{1B}[22;25m", nil),
    ]
    for (prefix, expected) in cases {
      #expect(await firstCell(after: prefix).style == expected, "\(prefix.debugDescription)")
    }
  }

  @Test("reverse video survives default terminal colors")
  func reverseVideoSurvivesDefaultColors() async {
    let cases: [(String, ResolvedTextStyle?)] = [
      ("\u{1B}[7m", ResolvedTextStyle(emphasis: .reverse)),
      ("\u{1B}[31;7m", ResolvedTextStyle(foregroundColor: .red, emphasis: .reverse)),
      ("\u{1B}[42;7m", ResolvedTextStyle(backgroundColor: .green, emphasis: .reverse)),
      // Two concrete colors remain represented by their exact swap.
      ("\u{1B}[31;42;7m", ResolvedTextStyle(foregroundColor: .green, backgroundColor: .red)),
      ("\u{1B}[1;7m", ResolvedTextStyle(emphasis: [.bold, .reverse])),
      ("\u{1B}[7m\u{1B}[27m", nil),
    ]
    for (prefix, expected) in cases {
      #expect(await firstCell(after: prefix).style == expected, "\(prefix.debugDescription)")
    }
  }

  @Test("OSC 8 cells carry only the URI destination")
  func hyperlinkCellsCarryOnlyTheURI() async {
    let url = "https://example.com/a"
    func links(_ text: String) async -> [String?] {
      let emulator = TerminalEmulator(size: CellSize(width: 6, height: 1))
      _ = await emulator.feed(Array(text.utf8))
      return (await emulator.snapshot()).cells[0].prefix(4).map(\.hyperlink)
    }
    #expect(await links("\u{1B}]8;;\(url)\u{1B}\\abc\u{1B}]8;;\u{1B}\\d") == [url, url, url, nil])
    #expect(await links("\u{1B}]8;id=x1;\(url)\u{1B}\\X") == [url, nil, nil, nil])
    #expect(await links("\u{1B}]8;;\(url);b\u{07}X") == ["\(url);b", nil, nil, nil])
    #expect(
      await links("\u{1B}]8;;\(url)\u{1B}\\A\u{1B}]8;id=x1;\u{1B}\\B") == [url, nil, nil, nil])
  }

  @Test("pixel-size reports describe the virtual graphics cell")
  func pixelReportsDescribeTheGraphicsCell() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    let cell = await emulator.feed(Array("\u{1B}[16t".utf8))
    let area = await emulator.feed(Array("\u{1B}[14t".utf8))
    #expect(cell.contains(.clientReply(Array("\u{1B}[6;16;8t".utf8))))
    #expect(area.contains(.clientReply(Array("\u{1B}[4;48;80t".utf8))))
  }

  @Test("mouse-mode events follow control order independently of chunking")
  func mouseModeEventsFollowControlOrder() async {
    let input = Array("\u{1B}[?1006l\u{1B}[?1006h".utf8)
    let whole = mouseModes(await drainedEmulator().feed(input))
    #expect(whole == [.disabled, .sgr])
    for split in 1..<input.count {
      let emulator = await drainedEmulator()
      var events = await emulator.feed(Array(input[..<split]))
      events += await emulator.feed(Array(input[split...]))
      #expect(mouseModes(events) == whole, "split at byte \(split)")
    }
    let titled = await drainedEmulator().feed(Array("\u{1B}[?1006h\u{1B}]0;t\u{07}".utf8))
    #expect(titled == [.mouseModeChanged(.sgr), .titleChanged("t")])
    let combined = await drainedEmulator().feed(Array("\u{1B}[?1000;1006h".utf8))
    #expect(mouseModes(combined) == [.button, .sgr])
  }

  @Test("mouse tracking and encoding neighbors keep their events")
  func mouseTrackingNeighborsKeepTheirEvents() async {
    func modes(_ text: String) async -> [TerminalMouseMode] {
      mouseModes(await drainedEmulator().feed(Array(text.utf8)))
    }
    #expect(await modes("\u{1B}[?1000h\u{1B}[?1006h") == [.button, .sgr])
    #expect(await modes("\u{1B}[?1003h") == [.anyEvent])
    #expect(await modes("\u{1B}[?1000l") == [.disabled])
    #expect(await modes("\u{1B}[?1016h") == [.sgr])
    #expect(await modes("\u{1B}[?1016l") == [.disabled])
    #expect(await modes("\u{1B}[?2004h\u{1B}[?25l").isEmpty)
    #expect(await modes("\u{1B}[1006h").isEmpty)
    #expect(await modes("?1006h").isEmpty)
    let tracking = await drainedEmulator()
    _ = await tracking.feed(Array("\u{1B}[?1000h\u{1B}[?1006l".utf8))
    #expect(await tracking.captureSnapshot().mouseTracking)
  }
}

private func firstCell(after prefix: String) async -> RasterCell {
  let emulator = TerminalEmulator(size: CellSize(width: 5, height: 1))
  _ = await emulator.feed(Array((prefix + "X").utf8))
  return (await emulator.snapshot()).cells[0][0]
}

/// SwiftTerm announces its initial (disabled) mouse mode during construction;
/// the first feed drains that notification. Start from a drained emulator.
private func drainedEmulator() async -> TerminalEmulator {
  let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
  _ = await emulator.feed([])
  return emulator
}

private func mouseModes(_ events: [TerminalEmulatorEvent]) -> [TerminalMouseMode] {
  events.compactMap { event -> TerminalMouseMode? in
    guard case .mouseModeChanged(let mode) = event else { return nil }
    return mode
  }
}

private func captureStandardOutput(
  _ operation: () async -> Void
) async throws -> String {
  // A regular file cannot fill like an undrained pipe or wait for EOF from an
  // inherited child descriptor. The native gate also serializes tests because
  // stdout is process-wide, even when this suite itself is serialized.
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("terminal-view-stdout-\(UUID().uuidString)")
  try Data().write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let capture = try FileHandle(forWritingTo: url)
  fflush(nil)
  let original = dup(STDOUT_FILENO)
  guard original >= 0 else { throw POSIXError(.EBADF) }
  defer {
    fflush(nil)
    dup2(original, STDOUT_FILENO)
    close(original)
    try? capture.close()
  }
  guard dup2(capture.fileDescriptor, STDOUT_FILENO) >= 0 else { throw POSIXError(.EBADF) }
  await operation()
  fflush(nil)
  return String(decoding: try Data(contentsOf: url), as: UTF8.self)
}
