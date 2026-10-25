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

  @Test("backend diagnostics for child sequences stay off the host's standard output")
  func backendDiagnosticsStayOffHostStandardOutput() async throws {
    // SwiftTerm prints these to the host process's stdout despite silentLog (STUI-1258).
    let inputs: [[UInt8]] =
      [
        "\u{1B}[1;1'z", "\u{1B}['z", "\u{1B}[2;1'z", "\u{1B}[6m", "\u{1B}[53m", "\u{1B}[99999m",
        "\u{1B}[1;6;31m", "\u{1B}[48;7;6m", "\u{1B}[6;m", "\u{1B}[6\u{1B}[6m", "\u{1B}[6\u{07}m",
        "\u{1B}P\u{1B}[6m\u{1B}\\", "\u{1B}]0;a\u{1B}\u{1B}[6m\u{07}", "\u{1B}[1;1'z\u{1B}[6m",
        "\u{1B}[:6m",
      ].map { Array($0.utf8) } + [
        [27, 91, 54, 0x7F, 109],
        // 8-bit C1 controls that the backend interprets inside a sequence or string.
        [27, 0x9B, 54, 109], [27, 91, 0x9B, 54, 109], [27, 32, 0x9B, 54, 109],
        [27, 93, 0x9B, 54, 109, 7], [27, 80, 0x9B, 54, 109, 27, 92],
        [27, 88, 0x9B, 54, 109, 27, 92], [27, 0x9B, 49, 39, 122],
      ]
    for input in inputs {
      let emulator = TerminalEmulator(size: CellSize(width: 10, height: 2))
      let output = try await captureStandardOutput { _ = await emulator.feed(input) }
      #expect(output == "", "\(input)")
    }
  }

  @Test("a narrowing resize without scrollback keeps scroll-region output off stdout")
  func narrowingResizeWithoutScrollbackStaysQuiet() async throws {
    let emulator = TerminalEmulator(size: CellSize(width: 18, height: 6), scrollbackLimit: 0)
    let output = try await captureStandardOutput {
      _ = await emulator.feed(Array((String(repeating: "x", count: 60) + "\n").utf8))
      await emulator.resize(CellSize(width: 9, height: 6))
      _ = await emulator.feed(Array("\u{1B}[3r\u{1B}[6;1H\n".utf8))
    }
    withKnownIssue(
      """
      Unfiled (STUI-1258 audit): with no scrollback, SwiftTerm 1.20.0's narrowing reflow \
      leaves yBase stale, so a later line feed in a scroll region prints "scroll: bottomRow \
      …" to the host's stdout and skips the scroll (Terminal.swift:6607-6611)
      """
    ) {
      #expect(output == "")
    }
  }

  @Test("filtered child sequences keep everything the backend applies")
  func filteredSequencesKeepWhatTheBackendApplies() async {
    let styles: [(String, ResolvedTextStyle?)] = [
      ("\u{1B}[1;6;31m", ResolvedTextStyle(foregroundColor: .red, emphasis: .bold)),
      ("\u{1B}[6m", nil),
      ("\u{1B}[48;7;6m", nil),
      ("\u{1B}[38;5;6m", ResolvedTextStyle(foregroundColor: .cyan)),
      (
        "\u{1B}[38:2::10:20:30m",
        ResolvedTextStyle(foregroundColor: Color(red: 10 / 255, green: 20 / 255, blue: 30 / 255))
      ),
      ("\u{1B}[53;4:3m", ResolvedTextStyle(underlineStyle: TextLineStyle(pattern: .curly))),
      ("\u{1B}[;1m", ResolvedTextStyle(emphasis: .bold)),
      ("\u{1B}[1m\u{1B}[6;m", nil),
      // 25 parameters: the backend drops the whole sequence.
      ("\u{1B}[" + String(repeating: "1;", count: 24) + "6m", nil),
    ]
    for (prefix, expected) in styles {
      #expect(await firstCell(after: prefix).style == expected, "\(prefix.debugDescription)")
    }

    let locator = TerminalEmulator(size: CellSize(width: 4, height: 1))
    _ = await locator.feed(Array("\u{1B}[1;1'zAB".utf8))
    #expect((await locator.snapshot()).cells[0].map(\.character) == ["A", "B", " ", " "])
    let erase = TerminalEmulator(size: CellSize(width: 4, height: 1))
    _ = await erase.feed(Array("AB\u{1B}[1;1;1;1$z".utf8))
    #expect((await erase.snapshot()).cells[0].map(\.character) == [" ", "B", " ", " "])
    let bell = TerminalEmulator(size: CellSize(width: 4, height: 1))
    #expect(await bell.feed(Array("\u{1B}[6\u{07}mX".utf8)).contains(.bell))
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

  @Test("SGR-Pixels reports pixel positions in the virtual graphics cell")
  func sgrPixelReportsUseTheVirtualCell() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    let reply = await emulator.feed(Array("\u{1B}[16t\u{1B}[?1003h\u{1B}[?1016h".utf8))
    #expect(reply.contains(.clientReply(Array("\u{1B}[6;16;8t".utf8))))
    func packet(_ kind: TerminalEmulatorMouse.Kind, _ x: Int, _ y: Int) async -> String {
      let bytes = await emulator.send(mouse: .init(kind: kind, cell: CellPoint(x: x, y: y)))
      return String(decoding: bytes, as: UTF8.self)
    }
    #expect(await packet(.down(.primary), 4, 2) == "\u{1B}[<0;32;32M")
    #expect(await packet(.up(.primary), 4, 2) == "\u{1B}[<0;32;32m")
    #expect(await packet(.dragged(.primary), 5, 1) == "\u{1B}[<32;40;16M")
    #expect(await packet(.moved, 4, 2) == "\u{1B}[<35;32;32M")
    #expect(await packet(.scrolled(deltaX: 0, deltaY: 1), 4, 2) == "\u{1B}[<65;32;32M")
    #expect(await packet(.cancelled, 4, 2).isEmpty)
    // A child dividing by the reported 8x16 cell recovers the event's cell.
    for (x, y) in [(0, 0), (9, 2), (3, 1)] {
      let report = await packet(.down(.primary), x, y)
      let fields = report.dropFirst(3).dropLast().split(separator: ";").compactMap { Int($0) }
      #expect(fields == [0, x * 8, y * 16], "\(report.dropFirst())")
      #expect(fields.count == 3 && fields[1] / 8 == x && fields[2] / 16 == y)
    }
  }

  @Test("cell encodings ignore the pixel position")
  func cellEncodingsIgnoreThePixelPosition() async {
    func packet(
      _ emulator: TerminalEmulator, _ kind: TerminalEmulatorMouse.Kind, _ x: Int, _ y: Int
    ) async -> [UInt8] {
      await emulator.send(mouse: .init(kind: kind, cell: CellPoint(x: x, y: y)))
    }
    let sgr = TerminalEmulator(size: CellSize(width: 10, height: 3))
    _ = await sgr.feed(Array("\u{1B}[?1003h\u{1B}[?1006h".utf8))
    #expect(await packet(sgr, .down(.primary), 4, 2) == Array("\u{1B}[<0;5;3M".utf8))
    #expect(await packet(sgr, .up(.primary), 4, 2) == Array("\u{1B}[<0;5;3m".utf8))
    #expect(await packet(sgr, .dragged(.primary), 5, 1) == Array("\u{1B}[<32;6;2M".utf8))
    #expect(await packet(sgr, .moved, 4, 2) == Array("\u{1B}[<35;5;3M".utf8))
    #expect(
      await packet(sgr, .scrolled(deltaX: 0, deltaY: 1), 4, 2) == Array("\u{1B}[<65;5;3M".utf8))

    let encodings: [(control: String, x: Int, packet: [UInt8])] = [
      ("", 4, [27, 91, 77, 32, 37, 35]),
      ("\u{1B}[?1015h", 4, Array("\u{1B}[32;5;3M".utf8)),
      ("\u{1B}[?1005h", 100, [27, 91, 77, 32, 0xC2, 0x85, 35]),
    ]
    for encoding in encodings {
      let emulator = TerminalEmulator(size: CellSize(width: 120, height: 3))
      _ = await emulator.feed(Array(("\u{1B}[?1000h" + encoding.control).utf8))
      #expect(
        await packet(emulator, .down(.primary), encoding.x, 2) == encoding.packet,
        "\(encoding.control.dropFirst())")
    }

    // Scaling to pixels must not add an overflow trap to any encoding.
    let far = Int.max / 4
    let extreme = TerminalEmulator(size: CellSize(width: 10, height: 3))
    _ = await extreme.feed(Array("\u{1B}[?1006h".utf8))
    #expect(
      await packet(extreme, .down(.primary), far, 2) == Array("\u{1B}[<0;\(far + 1);3M".utf8))
    _ = await extreme.feed(Array("\u{1B}[?1016h".utf8))
    #expect(
      await packet(extreme, .down(.primary), far, 2) == Array("\u{1B}[<0;\(Int.max);32M".utf8))
  }

  @Test("mouse-mode events follow control order independently of chunking")
  func mouseModeEventsFollowControlOrder() async {
    // Start from SGR so that the reset changes the encoding the backend applies.
    let input = Array("\u{1B}[?1006l\u{1B}[?1006h".utf8)
    let whole = mouseModes(await sgrEmulator().feed(input))
    #expect(whole == [.disabled, .sgr])
    for split in 1..<input.count {
      let emulator = await sgrEmulator()
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
    let pixels = await drainedEmulator()
    _ = await pixels.feed(Array("\u{1B}[?1016h".utf8))
    #expect(mouseModes(await pixels.feed(Array("\u{1B}[?1016l".utf8))) == [.disabled])
    #expect(await modes("\u{1B}[?2004h\u{1B}[?25l").isEmpty)
    #expect(await modes("\u{1B}[1006h").isEmpty)
    #expect(await modes("?1006h").isEmpty)
    let tracking = await drainedEmulator()
    _ = await tracking.feed(Array("\u{1B}[?1000h\u{1B}[?1006l".utf8))
    #expect(await tracking.captureSnapshot().mouseTracking)
  }

  @Test("one control sequence publishes tracking values before encoding values")
  func mouseModeOrderWithinOneSequence() async {
    #expect(await mouseModes(after: "\u{1B}[?1006;1000h") == [.button, .sgr])
    #expect(await mouseModes(after: "\u{1B}[?1006h\u{1B}[?1000h") == [.sgr, .button])
    #expect(await mouseModes(after: "\u{1B}[?1016;1003h") == [.anyEvent, .sgr])
    let emulator = await drainedEmulator()
    _ = await emulator.feed(Array("\u{1B}[?1000h\u{1B}[?1006h".utf8))
    let reset = await emulator.feed(Array("\u{1B}[?1006;1000l".utf8))
    #expect(mouseModes(reset) == [.disabled, .disabled])
    #expect(await emulator.captureSnapshot().mouseTracking == false)
  }

  @Test("encoding controls are independent of tracking and only SGR changes publish")
  func encodingControlsAreIndependentOfTracking() async {
    let reverted = await drainedEmulator()
    let events = await reverted.feed(Array("\u{1B}[?1002h\u{1B}[?1006h\u{1B}[?1006l".utf8))
    #expect(mouseModes(events) == [.button, .sgr, .disabled])
    #expect(await reverted.captureSnapshot().mouseTracking)
    #expect(await reverted.send(mouse: primaryPress) == x10PrimaryPress)

    for control in ["\u{1B}[?1005h", "\u{1B}[?1015h", "\u{1B}[?1005l", "\u{1B}[?1015l"] {
      #expect(await mouseModes(after: control).isEmpty, "\(control.dropFirst())")
    }

    let urxvt = await drainedEmulator()
    #expect(
      mouseModes(await urxvt.feed(Array("\u{1B}[?1006h\u{1B}[?1015h".utf8))) == [.sgr, .disabled])
    #expect(await urxvt.send(mouse: primaryPress) == Array("\u{1B}[32;5;3M".utf8))

    let utf8 = await drainedEmulator(width: 120)
    #expect(
      mouseModes(await utf8.feed(Array("\u{1B}[?1006h\u{1B}[?1005h".utf8))) == [.sgr, .disabled])
    let wide = TerminalEmulatorMouse(kind: .down(.primary), cell: CellPoint(x: 100, y: 2))
    #expect(await utf8.send(mouse: wide) == [27, 91, 77, 32, 0xC2, 0x85, 35])

    let restored = await drainedEmulator()
    #expect(
      mouseModes(await restored.feed(Array("\u{1B}[?1006h\u{1B}[?1015l".utf8)))
        == [.sgr, .disabled])
    #expect(await restored.send(mouse: primaryPress) == x10PrimaryPress)
  }

  @Test("tracking notifications record each control rather than a state change")
  func trackingNotificationsRecordEachControl() async {
    let constructed = TerminalEmulator(size: CellSize(width: 10, height: 3))
    #expect(mouseModes(await constructed.feed([])) == [.disabled])
    let levels: [(String, TerminalMouseMode)] = [
      ("\u{1B}[?1000h", .button), ("\u{1B}[?1002h", .button), ("\u{1B}[?9h", .x10),
    ]
    for (control, mode) in levels {
      let emulator = await drainedEmulator()
      #expect(mouseModes(await emulator.feed(Array(control.utf8))) == [mode])
      #expect(await emulator.captureSnapshot().mouseTracking)
    }
    #expect(await mouseModes(after: "\u{1B}[?1000h\u{1B}[?1000h") == [.button, .button])
    #expect(await mouseModes(after: "\u{1B}[?1003l") == [.disabled])
    let exclusive = await drainedEmulator()
    let events = await exclusive.feed(Array("\u{1B}[?1000h\u{1B}[?1003l".utf8))
    #expect(mouseModes(events) == [.button, .disabled])
    #expect(await exclusive.captureSnapshot().mouseTracking == false)

    let reset = await drainedEmulator()
    _ = await reset.feed(Array("\u{1B}[?1003h\u{1B}[?1006h".utf8))
    #expect(mouseModes(await reset.feed(Array("\u{1B}c".utf8))) == [.disabled])
    #expect(await reset.captureSnapshot().mouseTracking == false)
    #expect(mouseModes(await reset.feed(Array("\u{1B}[?1000h".utf8))) == [.button])
    #expect(await reset.send(mouse: primaryPress) == Array("\u{1B}[<0;5;3M".utf8))
  }

  @Test("the documented fold recovers the tracking state that the last event misstates")
  func mouseStateFoldRecoversTrackingLevel() async {
    let emulator = await drainedEmulator()
    #expect(await emulator.captureSnapshot().mouseTracking == false)
    #expect(await emulator.send(mouse: primaryPress) == x10PrimaryPress)

    let steps: [(control: String, state: TerminalMouseMode, lastEventAgrees: Bool)] = [
      ("\u{1B}[?1003h", .anyEvent, true),
      ("\u{1B}[?1006h", .anyEvent, false),
      ("\u{1B}[?1006l", .anyEvent, false),
      ("\u{1B}[?1000l", .disabled, true),
      ("\u{1B}[?1006h", .disabled, false),
      ("\u{1B}[?9h", .x10, true),
      ("\u{1B}[?1016h", .x10, false),
      ("\u{1B}[?1016l", .x10, false),
      ("\u{1B}c", .disabled, true),
      ("\u{1B}[?1002h", .button, true),
      ("\u{1B}[?1015h", .button, true),
    ]
    var level = TerminalMouseMode.disabled
    var lastEvent: TerminalMouseMode?
    for step in steps {
      for mode in mouseModes(await emulator.feed(Array(step.control.utf8))) {
        lastEvent = mode
        if mode == .x10 || mode == .button || mode == .anyEvent { level = mode }
      }
      let state = await emulator.captureSnapshot().mouseTracking ? level : .disabled
      #expect(state == step.state, "\(step.control.dropFirst())")
      #expect((lastEvent == step.state) == step.lastEventAgrees, "\(step.control.dropFirst())")
    }
  }
}

private let primaryPress = TerminalEmulatorMouse(kind: .down(.primary), cell: CellPoint(x: 4, y: 2))
/// `primaryPress` in the default X10 encoding: CSI M, then button and 1-based ordinates plus 32.
private let x10PrimaryPress: [UInt8] = [27, 91, 77, 32, 37, 35]

private func mouseModes(after text: String) async -> [TerminalMouseMode] {
  mouseModes(await drainedEmulator().feed(Array(text.utf8)))
}

private func firstCell(after prefix: String) async -> RasterCell {
  let emulator = TerminalEmulator(size: CellSize(width: 5, height: 1))
  _ = await emulator.feed(Array((prefix + "X").utf8))
  return (await emulator.snapshot()).cells[0][0]
}

/// SwiftTerm announces its initial (disabled) mouse mode during construction;
/// the first feed drains that notification. Start from a drained emulator.
private func drainedEmulator(width: Int = 10) async -> TerminalEmulator {
  let emulator = TerminalEmulator(size: CellSize(width: width, height: 3))
  _ = await emulator.feed([])
  return emulator
}

/// A drained emulator whose child has selected SGR mouse encoding.
private func sgrEmulator() async -> TerminalEmulator {
  let emulator = await drainedEmulator()
  _ = await emulator.feed(Array("\u{1B}[?1006h".utf8))
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
